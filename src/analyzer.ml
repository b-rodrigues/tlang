(* src/analyzer.ml *)

open Ast
open Symbol_table
open Semantic_type

type semantic_env = Symbol_table.scope

module Definition_map = Map.Make (String)

type analysis_result = {
  definitions : Ast.source_location Definition_map.t;
}

let csv_cache = Hashtbl.create 10

(** Infer the semantic type of an AST expression.
    
    Traverses the expression structure recursively, utilizing the provided symbol
    scope to lookup variable types, resolve function calls, parse CSV column headers,
    and process complex nodes (lambdas, list literals, blocks, matches).
    
    @param scope The symbol table scope.
    @param expr The AST expression to check.
    @return The inferred semantic type. *)
let rec infer_type scope expr =
  match expr.node with
  | Value v -> 
      (match Symbol_table.value_to_semantic_type v with
       | Some ty -> ty
       | None -> TUnknown)
  | Var name ->
      (match Symbol_table.lookup scope name with
       | Some s -> (match s.typ with Some ty -> ty | None -> TUnknown)
       | None -> TUnknown)
  | ColumnRef name ->
      Symbol_table.add_observed_column scope name;
      TUnknown

  | Call { fn = { node = Var ("filter" | "arrange" | "group_by" | "ungroup"); _ }; args = (None, data_expr) :: rest; _ } ->
      List.iter (fun (_, e) -> ignore (infer_type scope e)) rest;
      infer_type scope data_expr
  | Call { fn = { node = Var "select"; _ }; args = (None, data_expr) :: rest; _ } ->
      let base_ty = infer_type scope data_expr in
      let selected = List.filter_map (fun (_, e) ->
        match e.node with Value (VString col_name) -> Some col_name | _ -> None
      ) rest in
      (match base_ty, selected with
       | TDataFrame cols, names ->
           let filtered = List.filter (fun c -> List.mem c.name names) cols in
           TDataFrame filtered
       | _ -> base_ty)
  | Call { fn = { node = Var "read_csv"; _ }; args = (None, { node = Value (VString path); _ }) :: rest; _ } ->
      List.iter (fun (_, e) -> ignore (infer_type scope e)) rest;
      let cols =
        match Hashtbl.find_opt csv_cache path with
        | Some cols -> cols
        | None ->
          let cols = 
            try
              let chan = open_in path in
              Fun.protect
                ~finally:(fun () -> close_in chan)
                (fun () ->
                  let header = input_line chan in
                  let names =
                    if String.contains header ';'
                    then String.split_on_char ';' header
                    else String.split_on_char ',' header
                  in
                  List.map
                    (fun name ->
                      let name = String.trim name in
                      let name =
                        if String.starts_with ~prefix:"\"" name
                        then String.sub name 1 (String.length name - 2)
                        else name
                      in
                      { name; col_typ = TUnknown })
                    names)
            with Sys_error _ | End_of_file -> [] (* path not readable; columns unknown *)
          in
          Hashtbl.add csv_cache path cols;
          cols
      in
      TDataFrame cols
  | Call { fn = { node = Var "read_parquet"; _ }; args; _ } ->
      List.iter (fun (_, e) -> ignore (infer_type scope e)) args;
      TDataFrame []
  | Call { fn = { node = Var "to_dataframe"; _ }; args; _ } ->
      let rec find_list = function
        | [] -> []
        | (None, { node = ListLit items; _ }) :: _ -> items
        | _ :: rest -> find_list rest
      in
      let items = find_list args in
      List.iter (fun (_, e) -> ignore (infer_type scope e)) args;
      let cols = List.filter_map (function
        | (Some name, _) -> Some { name; col_typ = TUnknown }
        | _ -> None
      ) items in
      TDataFrame cols
  | Call { fn = { node = Var "mutate"; _ }; args; _ } ->
      let base_ty = match args with (None, data_expr) :: _ -> infer_type scope data_expr | _ -> TUnknown in
      let mut_args = match args with _ :: rest -> rest | [] -> [] in
      let new_cols = List.filter_map (function
        | (Some col_name, expr) ->
            let col_typ = infer_type scope expr in
            Some { name = col_name; col_typ }
        | (None, { node = Value (VString col_name); _ }) -> Some { name = col_name; col_typ = TUnknown }
        | (None, expr) ->
            ignore (infer_type scope expr);
            None
      ) mut_args in
      (match base_ty with
       | TDataFrame cols -> TDataFrame (new_cols @ cols)
       | TGroupedDataFrame (cols, g) -> TGroupedDataFrame (new_cols @ cols, g)
       | _ -> base_ty)
  | Call { fn; args; _ } ->
      let fn_t = infer_type scope fn in
      List.iter (fun (_, e) -> ignore (infer_type scope e)) args;
      (match fn_t with
       | TFunction (_, ret) -> ret
       | _ -> TUnknown)

  | Lambda { params; body; _ } ->
      let args = List.map (fun name -> (name, TUnknown)) params in
      let ret = infer_type scope body in
      TFunction (args, ret)
  | ListLit items ->
      let types = List.filter_map (fun (_, e) ->
        let t = infer_type scope e in
        if t = TUnknown || t = TAny then None else Some t
      ) items in
      (match types with
       | [] -> TAny
       | t :: rest when List.for_all ((=) t) rest -> t
       | _ -> TAny)
  | IfElse { cond; then_; else_ } ->
      ignore (infer_type scope cond);
      let tt = infer_type scope then_ in
      let et = infer_type scope else_ in
      begin match (tt, et) with
      | (t1, t2) when t1 = t2 -> t1
      | (TInt, TFloat) | (TFloat, TInt) -> TFloat
      | (TUnknown, t) | (t, TUnknown) -> t
      | _ -> TUnknown
      end
  | Match { scrutinee; cases } ->
      ignore (infer_type scope scrutinee);
      let types = List.filter_map (fun (_, body) ->
        let t = infer_type scope body in
        if t = TUnknown then None else Some t
      ) cases in
      begin match types with
      | [] -> TUnknown
      | t :: rest when List.for_all ((=) t) rest -> t
      | _ -> TUnknown
      end
  | BinOp { op = (Plus | Minus | Mul); left; right } ->
      let lt = infer_type scope left in
      let rt = infer_type scope right in
      begin match (lt, rt) with
      | (TInt, TInt) -> TInt
      | (TFloat, _) | (_, TFloat) -> TFloat
      | _ -> TUnknown
      end
  | BinOp { op = Div; left; right } ->
      ignore (infer_type scope left);
      ignore (infer_type scope right);
      TFloat  (* Division always returns Float in T *)
  | BinOp { op = Mod; left; right } ->
      let lt = infer_type scope left in
      let rt = infer_type scope right in
      begin match (lt, rt) with
      | (TInt, TInt) -> TInt
      | (TFloat, _) | (_, TFloat) -> TFloat
      | _ -> TUnknown
      end
  | BinOp { op = (Eq | NEq | Gt | Lt | GtEq | LtEq | And | Or | In); left; right } ->
      ignore (infer_type scope left);
      ignore (infer_type scope right);
      TBool
  | BroadcastOp { left; right; _ } ->
      ignore (infer_type scope left);
      ignore (infer_type scope right);
      TUnknown
  | UnOp { op = Not; _ } ->
      TBool
  | UnOp { op = Neg; operand } ->
      infer_type scope operand
  | DotAccess { target; field } ->
      let tt = infer_type scope target in
      begin match tt with
      | TDataFrame cols ->
          (match List.find_opt (fun c -> c.name = field) cols with
           | Some c -> c.col_typ
           | None -> TUnknown)
      | TGroupedDataFrame (cols, _) ->
          (match List.find_opt (fun c -> c.name = field) cols with
           | Some c -> c.col_typ
           | None -> TUnknown)
      | _ -> TUnknown
      end
  | PipelineDef nodes | PipelineOfDef nodes | IntentDef nodes ->
      List.iter (fun (_, e) -> ignore (infer_type scope e)) nodes;
      TUnknown
  | Block stmts ->
      List.iter (fun s -> analyze_stmt scope (ref Definition_map.empty) s) stmts;
      TUnknown
  | _ -> TUnknown

(** Add a source code definition location to the definition map.
    
    @param definitions The definition map reference to update.
    @param name The name of the defined symbol.
    @param loc The source location of the definition. *)
and add_definition definitions name = function
  | Some loc ->
      definitions :=
        Definition_map.update name
          (function None -> Some loc | Some existing -> Some existing)
          !definitions
  | _ -> ()

(** Analyze a statement semantically.
    
    Infers the types of assigned expressions, populates the symbol table scope,
    and records the locations of symbol definitions.
    
    @param scope The symbol table scope.
    @param definitions The definition map reference to update.
    @param stmt The statement to analyze. *)
and analyze_stmt scope definitions stmt =
  match stmt.node with
  | Assignment { name; expr; _ } ->
      let ty = infer_type scope expr in
      Symbol_table.add scope { name; kind = Variable; typ = Some ty; doc = None };
      add_definition definitions name stmt.loc
  | Reassignment { name; expr } ->
      let ty = infer_type scope expr in
      Symbol_table.add scope { name; kind = Variable; typ = Some ty; doc = None }
  | ImportPackage pkg_name ->
      (match List.find_opt (fun p -> p.Packages.name = pkg_name) Packages.all_packages with
       | Some pkg ->
           let funcs = Packages.package_functions pkg in
           List.iter (fun f ->
             Symbol_table.add scope { name = f; kind = Function; typ = Some TUnknown; doc = None }
           ) funcs
       | None -> ())
  | ImportFrom { package; names } ->
      (match List.find_opt (fun p -> p.Packages.name = package) Packages.all_packages with
       | Some pkg ->
           let funcs = Packages.package_functions pkg in
           List.iter (fun (import_item : Ast.import_spec) ->
             if List.mem import_item.import_name funcs then
               let name = Option.value ~default:import_item.import_name import_item.import_alias in
               Symbol_table.add scope { name; kind = Function; typ = Some TUnknown; doc = None }
           ) names
       | None -> ())
  | Expression e -> ignore (infer_type scope e)
  | _ -> ()

(** Perform complete semantic analysis on a parsed T program.
    
    Builds the symbol table scope, infers all variable types, and maps all defined
    symbols to their original source code locations.
    
    @param program The parsed program (list of statements) to analyze.
    @param scope The symbol table scope to populate.
    @return An [analysis_result] containing all resolved symbol definitions. *)
let analyze program scope =
  let definitions = ref Definition_map.empty in
  List.iter (analyze_stmt scope definitions) program;
  { definitions = !definitions }

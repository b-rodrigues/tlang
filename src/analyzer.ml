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

  | Call { fn = { node = Var ("filter" | "select" | "arrange" | "group_by" | "ungroup"); _ }; args = (None, data_expr) :: rest; _ } ->
      List.iter (fun (_, e) -> ignore (infer_type scope e)) rest;
      infer_type scope data_expr
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
            with _ -> []
          in
          Hashtbl.add csv_cache path cols;
          cols
      in
      TDataFrame cols
  | Call { fn = { node = Var "read_parquet"; _ }; args; _ } ->
      List.iter (fun (_, e) -> ignore (infer_type scope e)) args;
      TDataFrame []
  | Call { fn = { node = Var "dataframe"; _ }; args; _ } ->
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
      List.iter (fun (_, e) -> ignore (infer_type scope e)) mut_args;
      let new_cols = List.filter_map (function
        | (None, { node = Value (VString col_name); _ }) -> Some { name = col_name; col_typ = TUnknown }
        | (Some col_name, _) -> Some { name = col_name; col_typ = TUnknown }
        | _ -> None
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
      ignore (infer_type scope body);
      TFunction (args, TUnknown)
  | ListLit items ->
      List.iter (fun (_, e) -> ignore (infer_type scope e)) items;
      TAny
  | IfElse { cond; then_; else_ } ->
      ignore (infer_type scope cond);
      ignore (infer_type scope then_);
      ignore (infer_type scope else_);
      TUnknown
  | BinOp { left; right; _ } | BroadcastOp { left; right; _ } ->
      ignore (infer_type scope left);
      ignore (infer_type scope right);
      TUnknown
  | UnOp { operand; _ } ->
      ignore (infer_type scope operand);
      TUnknown
  | DotAccess { target; _ } ->
      ignore (infer_type scope target);
      TUnknown
  | PipelineDef nodes | IntentDef nodes ->
      List.iter (fun (_, e) -> ignore (infer_type scope e)) nodes;
      TUnknown
  | Block stmts ->
      List.iter (fun s -> analyze_stmt scope (ref Definition_map.empty) s) stmts;
      TUnknown
  | _ -> TUnknown

and add_definition definitions name = function
  | Some loc ->
      definitions :=
        Definition_map.update name
          (function None -> Some loc | Some existing -> Some existing)
          !definitions
  | _ -> ()

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

let analyze program scope =
  let definitions = ref Definition_map.empty in
  List.iter (analyze_stmt scope definitions) program;
  { definitions = !definitions }

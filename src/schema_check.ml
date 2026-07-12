(* src/schema_check.ml *)
(* Static schema propagation and column reference validation for t check --schema (tier 2) *)

open Ast

(* A schema is a list of column names. Types are not tracked statically. *)
type schema = string list

(* ---------- AST column reference extraction ---------- *)

(* Extract all column references from an AST expression.
   Handles ColumnRef ($col), DotAccess (df.col), and recursively
   enters lambdas, calls, binary ops, etc. *)
let rec extract_col_refs ?(param="row") expr =
  match expr.node with
  | ColumnRef field -> [field]
  | DotAccess { target = { node = Var p; _ }; field } when p = param -> [field]
  | DotAccess { target; _ } -> extract_col_refs ~param target
  | BinOp { left; right; _ } ->
      extract_col_refs ~param left @ extract_col_refs ~param right
  | BroadcastOp { left; right; _ } ->
      extract_col_refs ~param left @ extract_col_refs ~param right
  | UnOp { operand; _ } -> extract_col_refs ~param operand
  | Call { fn; args } ->
      extract_col_refs ~param fn @
      List.concat_map (fun (_, e) -> extract_col_refs ~param e) args
  | Lambda { params; body; _ } ->
      let inner_param = match params with p :: _ -> p | [] -> param in
      extract_col_refs ~param:inner_param body
  | IfElse { cond; then_; else_ } ->
      extract_col_refs ~param cond @
      extract_col_refs ~param then_ @
      extract_col_refs ~param else_
  | ListLit items -> List.concat_map (fun (_, e) -> extract_col_refs ~param e) items
  | DictLit pairs -> List.concat_map (fun (_, e) -> extract_col_refs ~param e) pairs
  | Value _ | Var _ | ShellExpr _ | RawCode _ -> []
  | Block stmts ->
      List.concat_map (fun s ->
        match s.node with
        | Expression e -> extract_col_refs ~param e
        | Assignment { expr; _ } | Reassignment { expr; _ } ->
            extract_col_refs ~param expr
        | _ -> []
      ) stmts
  | Match { scrutinee; cases } ->
      extract_col_refs ~param scrutinee @
      List.concat_map (fun (_, body) -> extract_col_refs ~param body) cases
  | _ -> []

(* ---------- read_csv path extraction ---------- *)

(* Try to extract the file path from a read_csv("path") call expression *)
let extract_read_csv_path expr =
  match expr.node with
  | Call { fn = { node = Var ("read_csv" | "t_read_csv"); _ }; args } ->
      (match args with
       | (_, { node = Value (VString path); _ }) :: _ -> Some path
       | _ -> None)
  | _ -> None

(* ---------- CSV header reading ---------- *)

(* Read the first line of a CSV file to extract column names.
   This is fast (~ms) and doesn't require Nix. *)
let read_csv_header path =
  try
    let ic = open_in path in
    let line = input_line ic in
    close_in ic;
    (* Split on comma, trim whitespace, strip quotes *)
    let cols = String.split_on_char ',' line in
    let cols = List.map (fun s ->
      let s = String.trim s in
      (* Strip surrounding quotes *)
      if String.length s >= 2 && s.[0] = '"' && s.[String.length s - 1] = '"'
      then String.sub s 1 (String.length s - 2)
      else s
    ) cols in
    Some cols
  with _ -> None

(* ---------- Schema inference for colcraft verbs ---------- *)

(* Determine the colcraft function being called in a pipe's right side *)
type verb =
  | Select
  | Filter
  | Mutate
  | Rename
  | Arrange
  | GroupBy
  | Summarize
  | Ungroup
  | Distinct
  | Slice
  | Count
  | Other of string

let classify_verb expr =
  match expr.node with
  | Call { fn = { node = Var name; _ }; _ } ->
      (match name with
       | "select" -> Select
       | "filter" | "t_filter" -> Filter
       | "mutate" -> Mutate
       | "rename" -> Rename
       | "arrange" -> Arrange
       | "group_by" -> GroupBy
       | "summarize" -> Summarize
       | "ungroup" -> Ungroup
       | "distinct" -> Distinct
       | "slice" | "slice_min" | "slice_max" | "slice_sample" -> Slice
       | "count" -> Count
       | _ -> Other name)
  | _ -> Other "unknown"

(* Extract column names from a select() call's arguments *)
let extract_select_cols args =
  List.filter_map (fun (_, e) ->
    match e.node with
    | ColumnRef col -> Some col
    | _ -> None
  ) args

(* Extract the new column name from a mutate() named argument.
   mutate(df, $new = expr) → Some "new"
   Best-effort: also treats a bare positional $col as a new column assignment,
   which may produce false positives on unusual mutate signatures. *)
let extract_mutate_new_cols args =
  List.filter_map (fun (name, e) ->
    match name with
    | Some col -> Some col
    | None ->
        (* Best-effort heuristic: bare $col positional arg treated as assignment *)
        (match e.node with
         | ColumnRef col -> Some col
         | _ -> None)
  ) args

(* Extract the new column names from a summarize() call.
   summarize(df, $avg = mean($mpg)) → ["avg"] *)
let extract_summarize_cols args =
  List.filter_map (fun (name, _e) ->
    match name with
    | Some col -> Some col
    | None -> None
  ) args

(* Infer the output schema of a node given its input schema and expression *)
let infer_output_schema input_schema expr =
  match classify_verb expr with
  | Select ->
      let cols = extract_select_cols
          (match expr.node with Call { args; _ } -> args | _ -> []) in
      if cols = [] then input_schema else cols
  | Filter | Ungroup | Slice | Arrange | GroupBy ->
      input_schema
  | Mutate ->
      let new_cols = extract_mutate_new_cols
          (match expr.node with Call { args; _ } -> args | _ -> []) in
      (* Remove any input cols being overwritten, then append new *)
      let old_cols = List.filter (fun c -> not (List.mem c new_cols)) input_schema in
      old_cols @ new_cols
  | Rename ->
      (* rename(df, $old, "new") — we can't fully parse this statically,
         just return input schema unchanged *)
      input_schema
  | Summarize ->
      extract_summarize_cols
        (match expr.node with Call { args; _ } -> args | _ -> [])
  | Distinct ->
      input_schema
  | Count ->
      let named = extract_summarize_cols
          (match expr.node with Call { args; _ } -> args | _ -> []) in
      if named <> [] then named else input_schema @ ["n"]
  | Other _ ->
      (* Unknown function — schema is unknown *)
      []

(* ---------- Pipe analysis ---------- *)

(* Unwrap a pipe chain: raw |> filter(...) |> mutate(...)
   Returns the list of operations left-to-right *)
let rec unwrap_pipe expr =
  match expr.node with
  | BinOp { op = Pipe; left; right } ->
      unwrap_pipe left @ [right]
  | _ -> [expr]

(* Check if an expression looks like a read_csv call *)
let is_read_csv expr =
  Option.is_some (extract_read_csv_path expr)

(* ---------- Column reference validation ---------- *)

(* Validate that all column references in an expression exist in the schema *)
let validate_col_refs ~node_name ~(file : string option) ~schema expr =
  let refs = extract_col_refs expr in
  let seen = Hashtbl.create 8 in
  List.filter_map (fun col ->
    if Hashtbl.mem seen col then None
    else begin
      Hashtbl.add seen col ();
      if List.mem col schema then None
      else Some (Diagnostics.{
        diag_id = Diagnostics.gen_id ();
        diag_error_class = "schema_mismatch";
        diag_severity = Error;
        diag_phase = Schema;
        diag_node_id = Some node_name;
        diag_node_lang = None;
        diag_file = file;
        diag_line = (match expr.loc with Some l -> Some l.line | None -> None);
        diag_column = (match expr.loc with Some l -> Some l.column | None -> None);
        diag_message = Printf.sprintf "Column '%s' referenced in node '%s' not found in input schema [%s]"
          col node_name (String.concat ", " schema);
        diag_caused_by = [];
        diag_suggested_fix = NoFix;
      })
    end
  ) refs

(* ---------- Contract validation ---------- *)

(* Validate contracts attached via expect() against inferred schemas.
   Checks that all declared contract columns exist in the output schema. *)
let validate_contracts ~file (p : pipeline_result) schemas =
  List.filter_map (fun (node_name, contract) ->
    let output_schema =
      try Hashtbl.find schemas node_name with Not_found -> []
    in
    match contract.contract_columns with
    | None -> None
    | Some required_cols ->
        let missing = List.filter (fun col -> not (List.mem col output_schema)) required_cols in
        if missing <> [] then
          Some (Diagnostics.{
            diag_id = Diagnostics.gen_id ();
            diag_error_class = "contract_violation";
            diag_severity = Error;
            diag_phase = Schema;
            diag_node_id = Some node_name;
            diag_node_lang = None;
            diag_file = Some file;
            diag_line = None;
            diag_column = None;
            diag_message = Printf.sprintf "Node '%s' contract expects columns [%s] but output schema is [%s]. Missing: [%s]"
              node_name
              (String.concat ", " required_cols)
              (String.concat ", " output_schema)
              (String.concat ", " missing);
            diag_caused_by = [];
            diag_suggested_fix = NoFix;
          })
        else None
  ) p.p_contracts

(* ---------- Main entry point ---------- *)

(* Check schemas for a pipeline. Returns Schema-phase diagnostics. *)
let check_pipeline_schemas ~(file : string) (p : pipeline_result) : Diagnostics.diagnostic list =
  let p_exprs = p.p_exprs in
  let p_deps = p.p_deps in
  let p_noops = p.p_noops in

  (* Topological order from deps *)
  let node_names = List.map fst p_exprs in
  let dep_of name = List.assoc_opt name p_deps |> Option.value ~default:[] in

  (* Compute topological order *)
  let topo_order =
    let visited = Hashtbl.create 16 in
    let order = ref [] in
    let rec visit name =
      if not (Hashtbl.mem visited name) then begin
        Hashtbl.add visited name ();
        List.iter visit (dep_of name);
        order := name :: !order
      end
    in
    List.iter visit node_names;
    List.rev !order
  in

  (* Propagate schemas through the DAG *)
  let schemas : (string, schema) Hashtbl.t = Hashtbl.create 16 in
  let diagnostics = ref [] in

  List.iter (fun name ->
    let is_noop = try List.assoc name p_noops with Not_found -> false in
    if is_noop then
      Hashtbl.add schemas name []
    else
      let expr = try List.assoc name p_exprs with Not_found -> mk_expr (Value (VNA NAGeneric)) in

      (* First, try to read CSV header for root nodes *)
      let root_schema =
        if is_read_csv expr then
          match extract_read_csv_path expr with
          | Some path ->
              (* Try relative to the file's directory *)
              let dir = Filename.dirname file in
              let full_path = Filename.concat dir path in
              (match read_csv_header full_path with
               | Some cols -> Some cols
               | None ->
                   (* Try the path as-is *)
                   match read_csv_header path with
                   | Some cols -> Some cols
                   | None -> None)
          | None -> None
        else None
      in

      (* Determine input schema from dependencies *)
      let input_schema = match dep_of name with
        | [] -> (match root_schema with Some s -> s | None -> [])
        | deps ->
            (* Use the schema of the primary dependency (the piped-from node) *)
            let primary = List.hd deps in
            (try Hashtbl.find schemas primary with Not_found -> [])
      in

      (* Infer output schema *)
      let output_schema = match root_schema with
        | Some cols -> cols
        | None ->
            (* Check if this is a pipe chain *)
            let ops = unwrap_pipe expr in
            if List.length ops > 1 then begin
              (* Pipe chain: the first element is the data source (Var ref),
                 subsequent elements are transformations. Start with input_schema. *)
              let final_schema = List.fold_left (fun acc_schema op ->
                match op.node with
                | Var _ -> acc_schema  (* Skip variable references — use accumulated schema *)
                | _ -> infer_output_schema acc_schema op
              ) input_schema ops in
              final_schema
            end else
              infer_output_schema input_schema expr
      in

      (* Store the schema *)
      if output_schema <> [] then
        Hashtbl.add schemas name output_schema;

      (* Validate column references in the expression *)
      let all_refs = unwrap_pipe expr in
      List.iter (fun op ->
        let validation_schema =
          if input_schema <> [] then input_schema
          else match dep_of name with
            | d :: _ -> (try Hashtbl.find schemas d with Not_found -> [])
            | [] -> []
        in
        if validation_schema <> [] then begin
          let errors = validate_col_refs ~node_name:name ~file:(Some file) ~schema:validation_schema op in
          diagnostics := errors @ !diagnostics
        end
      ) all_refs;

      (* Also validate formula variables if this is a lm() or similar call *)
      match expr.node with
      | Call { fn = { node = Var ("lm" | "predict" | "add_diagnostics" as fn_name); _ };
               args } ->
          (* Extract the formula argument *)
          let formula_arg = List.find_map (fun (_, e) ->
            match e.node with
            | BinOp { op = Formula; left; right } -> Some (left, right)
            | _ -> None
          ) args in
          (match formula_arg with
           | Some (lhs, rhs) ->
               let lhs_vars = extract_col_refs lhs in
               let rhs_vars = extract_col_refs rhs in
               let all_vars = lhs_vars @ rhs_vars in
               let validation_schema =
                 if input_schema <> [] then input_schema
                 else match dep_of name with
                   | d :: _ -> (try Hashtbl.find schemas d with Not_found -> [])
                   | [] -> []
               in
               if validation_schema <> [] then begin
                 let errors = List.filter_map (fun var ->
                   if not (List.mem var validation_schema) then
                     Some (Diagnostics.{
                       diag_id = Diagnostics.gen_id ();
                       diag_error_class = "schema_mismatch";
                       diag_severity = Error;
                       diag_phase = Schema;
                       diag_node_id = Some name;
                       diag_node_lang = None;
                        diag_file = Some file;
                       diag_line = (match expr.loc with Some l -> Some l.line | None -> None);
                       diag_column = (match expr.loc with Some l -> Some l.column | None -> None);
                       diag_message = Printf.sprintf "Formula variable '%s' in %s() not found in input schema [%s]"
                         var fn_name (String.concat ", " validation_schema);
                       diag_caused_by = [];
                       diag_suggested_fix = NoFix;
                     })
                   else None
                 ) all_vars in
                 diagnostics := errors @ !diagnostics
               end
           | None -> ())
      | _ -> ()
  ) topo_order;

  (* Validate contracts (expect() annotations) against computed schemas *)
  let contract_diags = validate_contracts ~file p schemas in
  contract_diags @ !diagnostics

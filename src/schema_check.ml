(* src/schema_check.ml *)
(* Static schema propagation and column reference validation for t check --schema (tier 2) *)

open Ast

(* A schema tracks column names with optional type information.
   Types are inferred from CSV headers and propagated through pipe chains. *)
type schema_col = { sc_name : string; sc_type : string option }
type schema = schema_col list

let schema_names (s : schema) : string list = List.map (fun c -> c.sc_name) s

let schema_has_col (col : string) (s : schema) : bool =
  List.exists (fun c -> c.sc_name = col) s

let schema_find_type (col : string) (s : schema) : string option =
  match List.find_opt (fun c -> c.sc_name = col) s with
  | Some c -> c.sc_type
  | None -> None

let make_schema ?(typed=[]) (cols : string list) : schema =
  List.map (fun name ->
    let sc_type = List.assoc_opt name typed in
    { sc_name = name; sc_type }
  ) cols

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

(* ---------- CSV schema reading with type inference ---------- *)

(* Strip quotes and whitespace from a CSV cell *)
let clean_csv_cell s =
  let s = String.trim s in
  if String.length s >= 2 && s.[0] = '"' && s.[String.length s - 1] = '"'
  then String.sub s 1 (String.length s - 2)
  else s

(* Split a CSV line into fields, respecting quoted strings that may contain commas.
   Does not handle escaped quotes within quoted fields. *)
let split_csv_line line =
  let buf = Buffer.create 64 in
  let cols = ref [] in
  let in_quotes = ref false in
  String.iter (fun c ->
    match c with
    | '"' -> in_quotes := not !in_quotes
    | ',' when not !in_quotes ->
        cols := Buffer.contents buf :: !cols;
        Buffer.clear buf
    | c -> Buffer.add_char buf c
  ) line;
  List.rev (Buffer.contents buf :: !cols)

(* Infer basic arrow type from a cell value string *)
let infer_type_from_cell value =
  let trimmed = String.trim value in
  try let _ = int_of_string trimmed in "int"
  with Failure _ ->
    try let _ = float_of_string trimmed in "double"
    with Failure _ -> "string"

(* Read the first line of a CSV file to extract column names (fast, no types).
   Kept for backward compatibility — prefer read_csv_schema for typed schemas. *)
let read_csv_header path =
  try
    let ic = open_in path in
    let line = input_line ic in
    close_in ic;
    let cols = split_csv_line line in
    Some (List.map clean_csv_cell cols)
  with _ -> None

(* Read CSV header + sample up to 5 data rows to infer column types.
   Peeks past empty/NA cells in the first row to find non-empty values per column.
   Fast (~ms) and doesn't require Nix. *)
let read_csv_schema path =
  try
    let ic = open_in path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      let header_line = input_line ic in
      let header_cols = split_csv_line header_line |> List.map clean_csv_cell in
      let num_cols = List.length header_cols in
      if num_cols = 0 then Some []
      else begin
        let samples = Array.init num_cols (fun _ -> "") in
        let remaining = ref num_cols in
        let max_peek = 5 in
        (try
           for _row = 1 to max_peek do
             if !remaining = 0 then raise Exit;
             (match try Some (input_line ic) with End_of_file -> None with
              | None -> raise Exit
              | Some line ->
                  let vals = split_csv_line line |> List.map clean_csv_cell in
                  let n = min num_cols (List.length vals) in
                  for i = 0 to n - 1 do
                    if String.length samples.(i) = 0 then begin
                      let v = String.trim (List.nth vals i) in
                      if String.length v > 0 then begin
                        samples.(i) <- v;
                        decr remaining
                      end
                    end
                  done)
           done
         with Exit -> ());
        let cols = List.mapi (fun i name ->
          let sc_type =
            if String.length samples.(i) > 0
            then Some (infer_type_from_cell samples.(i))
            else None
          in
          { sc_name = name; sc_type }
        ) header_cols in
        Some cols
      end
    )
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
  | Expect
  | DataSource
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
       | "expect" -> Expect
       | "read_csv" | "t_read_csv" -> DataSource
       | _ -> Other name)
  | _ -> Other "unknown"

(* Extract column names from a select() call's arguments *)
let extract_select_cols args =
  List.filter_map (fun (_, e) ->
    match e.node with
    | ColumnRef col -> Some col
    | _ -> None
  ) args

(* Extract the new column name and optionally its reported type from a mutate() arg.
   mutate(df, $new = expr) → Some ("new", expr_type)
   Detects as.TYPE() calls to propagate the target type.
   Best-effort: also treats a bare positional $col as a new column assignment,
   which may produce false positives on unusual mutate signatures. *)
let extract_mutate_new_cols args =
  let detect_coercion_type e =
    match e.node with
    | Call { fn = { node = Var fn_name; _ }; _ } ->
        (match fn_name with
         | "as.int" -> Some "int"
         | "as.double" | "as_numeric" -> Some "double"
         | "as.string" | "as_character" -> Some "string"
         | "as_logical" | "as_bool" -> Some "bool"
         | _ -> None)
    | Call { fn = { node = DotAccess { target = { node = Var "as"; _ }; field }; _ }; _ } ->
        (match field with
         | "int" -> Some "int"
         | "double" -> Some "double"
         | "string" -> Some "string"
         | "character" -> Some "string"
         | "logical" | "bool" -> Some "bool"
         | _ -> None)
    | _ -> None
  in
  List.filter_map (fun (name, e) ->
    let inferred_type = detect_coercion_type e in
    match name with
    | Some col -> Some (col, inferred_type)
    | None ->
        (match e.node with
         | ColumnRef col -> Some (col, None)
         | _ -> None)
  ) args

(* Infer types for summarize() aggregation columns.
   mean()/median() → double, n()/first()/last() → depends, others → None
   Returns the column name and its inferred type. *)
let extract_summarize_cols_with_types args =
  let detect_agg_type e =
    match e.node with
    | Call { fn = { node = Var fn_name; _ }; _ } ->
        (match fn_name with
         | "mean" | "median" | "sd" | "var" -> Some "double"
         | "n" | "n_distinct" | "first" | "last" -> Some "int"
         | "min" | "max" | "sum" -> None  (* depends on input type *)
         | _ -> None)
    | _ -> None
  in
  List.filter_map (fun (name, e) ->
    match name with
    | Some col -> Some (col, detect_agg_type e)
    | None -> None
  ) args

(* Infer the output schema of a node given its input schema and expression *)
let infer_output_schema input_schema expr =
  match classify_verb expr with
  | Select ->
      let cols = extract_select_cols
          (match expr.node with Call { args; _ } -> args | _ -> []) in
      if cols = [] then input_schema
      (* limitation: exclusion syntax (-$col, -c(...), and selections helpers like
         everything()/starts_with()) are not parsed — falls back to full input schema *)
      else List.map (fun c ->
        if schema_has_col c input_schema then
          { sc_name = c; sc_type = schema_find_type c input_schema }
        else
          { sc_name = c; sc_type = None }
      ) cols
  | Filter | Ungroup | Slice | Arrange | GroupBy | DataSource ->
      input_schema
  | Mutate ->
      let new_cols = extract_mutate_new_cols
          (match expr.node with Call { args; _ } -> args | _ -> []) in
      let new_col_names = List.map fst new_cols in
      let new_col_types = List.map (fun (n, t) -> (n, t)) new_cols in
      (* Remove any input cols being overwritten, then append new *)
      let old_cols = List.filter (fun c -> not (List.mem c.sc_name new_col_names)) input_schema in
      old_cols @ List.map (fun (name, t) -> { sc_name = name; sc_type = t }) new_col_types
  | Rename ->
      let args = match expr.node with Call { args; _ } -> args | _ -> [] in
      let mapping = List.filter_map (fun (name_opt, e) ->
        match name_opt, e.node with
        | Some new_name, ColumnRef old_name -> Some (old_name, new_name)
        | _ -> None
      ) args in
      if mapping = [] then input_schema
      else
        let old_names = List.map fst mapping in
        let preserved = List.filter (fun c -> not (List.mem c.sc_name old_names)) input_schema in
        let renamed = List.map (fun (old, new_) ->
          let sc_type = schema_find_type old input_schema in
          { sc_name = new_; sc_type }
        ) mapping in
        preserved @ renamed
  | Summarize ->
      let cols = extract_summarize_cols_with_types
          (match expr.node with Call { args; _ } -> args | _ -> []) in
      List.map (fun (name, t) -> { sc_name = name; sc_type = t }) cols
  | Distinct ->
      input_schema
  | Count ->
      (* approximation: real count() collapses to group-by columns + n.
         Keeping full input schema is overly permissive but safe. *)
      let named = extract_summarize_cols_with_types
          (match expr.node with Call { args; _ } -> args | _ -> []) in
      if named <> [] then
        List.map (fun (name, t) -> { sc_name = name; sc_type = t }) named
      else input_schema @ [{ sc_name = "n"; sc_type = Some "int" }]
  | Expect ->
      (* expect() is a schema annotation — pass through unchanged *)
      input_schema
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

(* Apply a single pipe-chain operation, advancing the schema.
   Skips Var references (data sources) since they don't transform the schema. *)
let apply_pipe_op schema op =
  match op.node with
  | Var _ -> schema
  | _ -> infer_output_schema schema op

(* ---------- Column reference validation ---------- *)

(* Extract the (old_name, new_name) mapping from a rename() call *)
let extract_rename_mapping expr =
  match classify_verb expr with
  | Rename ->
    (match expr.node with
     | Call { args; _ } ->
       List.filter_map (fun (name_opt, e) ->
         match name_opt, e.node with
         | Some new_name, ColumnRef old_name -> Some (old_name, new_name)
         | _ -> None
       ) args
     | _ -> [])
  | _ -> []

(* ---------- expect() contract extraction and validation ---------- *)

let extract_contracts args =
  List.filter_map (fun (name, e) ->
    match name, e.node with
    | Some "columns", ListLit items ->
        let cols = List.filter_map (fun (_, item) ->
          match item.node with
          | Value (VString s) -> Some s
          | _ -> None
        ) items in
        if cols <> [] then Some (Ast.Contract_columns cols) else None
    | _, BinOp { op = Formula; left = { node = Var col; _ }; right = { node = Call { fn = { node = Var t; _ }; _ }; _ } } ->
        Some (Ast.Contract_type (col, t))
    | _, BinOp { op = Lt;
              left = { node = Call { fn = { node = Var "null_rate"; _ };
                           args = [(_, { node = Value (VString col); _ })] }; _ };
              right = { node = Value (VFloat threshold); _ } } ->
        Some (Ast.Contract_null_rate (col, threshold))
    | _ -> None
  ) args

let validate_contracts ~node_name ~file ~chain_broken contracts output_schema =
  let diags = ref [] in
  List.iter (fun contract ->
    match contract with
    | Ast.Contract_columns cols ->
        List.iter (fun col ->
          if not (schema_has_col col output_schema) then
            diags := (Diagnostics.{
              diag_id = Diagnostics.gen_id ();
              diag_error_class = Contract_violation;
              diag_severity = Error;
              diag_phase = Schema;
              diag_node_id = Some node_name;
              diag_node_lang = None;
              diag_file = file;
              diag_line = None;
              diag_column = None;
              diag_end_line = None;
              diag_end_column = None;
              diag_message = Printf.sprintf "Expected column '%s' not found in output schema" col;
              diag_expected = Some col;
              diag_actual = None;
              diag_caused_by = [];
              diag_suggested_fix = Diagnostics.no_fix;
            } : Diagnostics.diagnostic) :: !diags
        ) cols
    | Ast.Contract_type (col, expected_type) ->
        (match schema_find_type col output_schema with
         | Some actual_type when actual_type <> expected_type ->
             diags := (Diagnostics.{
               diag_id = Diagnostics.gen_id ();
               diag_error_class = Contract_violation;
               diag_severity = Warning;
               diag_phase = Schema;
               diag_node_id = Some node_name;
               diag_node_lang = None;
               diag_file = file;
               diag_line = None;
               diag_column = None;
               diag_end_line = None;
               diag_end_column = None;
               diag_message = Printf.sprintf "Column '%s' type contract: expected '%s', got '%s'"
                 col expected_type actual_type;
               diag_expected = Some expected_type;
               diag_actual = Some actual_type;
               diag_caused_by = [];
               diag_suggested_fix =
                 if List.mem expected_type ["int"; "double"; "string"; "bool"]
                 then Diagnostics.make_cast_fix ~column:col ~cast_to:expected_type ~chain_broken ~target_node:node_name ?file ()
                 else Diagnostics.no_fix;
             } : Diagnostics.diagnostic) :: !diags
         | _ -> ())
    | Ast.Contract_null_rate (col, _threshold) ->
        if not (schema_has_col col output_schema) then
          diags := (Diagnostics.{
            diag_id = Diagnostics.gen_id ();
            diag_error_class = Contract_violation;
            diag_severity = Error;
            diag_phase = Schema;
            diag_node_id = Some node_name;
            diag_node_lang = None;
            diag_file = file;
            diag_line = None;
            diag_column = None;
            diag_end_line = None;
            diag_end_column = None;
            diag_message = Printf.sprintf "null_rate contract: column '%s' not found in output schema" col;
            diag_expected = Some col;
            diag_actual = None;
            diag_caused_by = [];
            diag_suggested_fix = Diagnostics.no_fix;
          } : Diagnostics.diagnostic) :: !diags
        else
          diags := (Diagnostics.{
            diag_id = Diagnostics.gen_id ();
            diag_error_class = Contract_unverifiable;
            diag_severity = Warning;
            diag_phase = Schema;
            diag_node_id = Some node_name;
            diag_node_lang = None;
            diag_file = file;
            diag_line = None;
            diag_column = None;
            diag_end_line = None;
            diag_end_column = None;
            diag_message = Printf.sprintf "null_rate contract for '%s' cannot be verified statically; requires runtime data" col;
            diag_expected = None;
            diag_actual = None;
            diag_caused_by = [];
            diag_suggested_fix = Diagnostics.no_fix;
          } : Diagnostics.diagnostic) :: !diags
  ) contracts;
  !diags

(* Validate that all column references in an expression exist in the schema *)
let validate_col_refs ~node_name ~(file : string option) ~schema ?(rename_mapping = []) expr =
  let refs = extract_col_refs expr in
  let seen = Hashtbl.create 8 in
  List.filter_map (fun col ->
    if Hashtbl.mem seen col then None
    else begin
      Hashtbl.add seen col ();
      if schema_has_col col schema then None
      else
        let suggested_fix = match List.assoc_opt col rename_mapping with
          | Some new_name ->
              let line = match expr.loc with Some l -> Some l.line | None -> None in
              (* structural rename, not a typo match — distance/uniqueness fields unused *)
              Diagnostics.make_rename_column_fix ~old_name:col ~new_name ~edit_distance:0 ~is_unique:true ~confidence:High ~target_node:node_name ?file ?line ()
          | None -> Diagnostics.no_fix
        in
        Some (Diagnostics.{
          diag_id = Diagnostics.gen_id ();
          diag_error_class = Schema_mismatch;
          diag_severity = Error;
          diag_phase = Schema;
          diag_node_id = Some node_name;
          diag_node_lang = None;
          diag_file = file;
          diag_line = (match expr.loc with Some l -> Some l.line | None -> None);
          diag_column = (match expr.loc with Some l -> Some l.column | None -> None);
          diag_end_line = None;
          diag_end_column = None;
          diag_message = Printf.sprintf "Column '%s' referenced in node '%s' not found in input schema [%s]"
            col node_name (String.concat ", " (schema_names schema));
          diag_expected = None;
          diag_actual = None;
          diag_caused_by = [];
          diag_suggested_fix = suggested_fix;
        })
    end
  ) refs

(* ---------- Main entry point ---------- *)

(* Check schemas for a pipeline. Returns Schema-phase diagnostics. *)
let check_pipeline_schemas ~(file : string) (p : pipeline_result) : Diagnostics.diagnostic list =
  let p_exprs = p.p_exprs in
  let p_deps = p.p_deps in
  let p_noops = p.p_noops in

  (* Topological order from deps *)
  let node_names = List.map fst p_exprs in
  let dep_of name =
    List.assoc_opt name p_deps
    |> Option.value ~default:[]
    |> List.filter (fun d -> List.mem d node_names)
  in

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
  let broken_nodes : (string, bool) Hashtbl.t = Hashtbl.create 16 in
  let diagnostics = ref [] in

  List.iter (fun name ->
    let is_noop = try List.assoc name p_noops with Not_found -> false in
    if is_noop then begin
      Hashtbl.add schemas name [];
      Hashtbl.add broken_nodes name false
    end else begin
      let expr = try List.assoc name p_exprs with Not_found -> mk_expr (Value (VNA NAGeneric)) in

      (* Determine if any dependency's schema was broken *)
      let dep_is_broken =
        List.exists (fun dep ->
          try Hashtbl.find broken_nodes dep with Not_found -> false
        ) (dep_of name)
      in

      (* Determine if the current node expression contains unrecognized verbs *)
      let ops = unwrap_pipe expr in
      let has_custom_verb = List.exists (fun op ->
        match op.node with
        | Var _ -> false
        | _ ->
            (match classify_verb op with
             | Other _ -> true
             | _ -> false)
      ) ops in

      let current_chain_broken = dep_is_broken || has_custom_verb in
      Hashtbl.add broken_nodes name current_chain_broken;

      (* First, try to read CSV header for root nodes *)
      let root_schema =
        if is_read_csv expr then
          match extract_read_csv_path expr with
          | Some path ->
              let dir = Filename.dirname file in
              let full_path = Filename.concat dir path in
              (match read_csv_schema full_path with
               | Some cols -> Some cols
               | None ->
                   let proj_schema =
                     try
                       let project_root = Builder_utils.get_project_root () in
                       let proj_path = Filename.concat project_root path in
                       read_csv_schema proj_path
                     with _ -> None
                   in
                   (match proj_schema with
                    | Some cols -> Some cols
                    | None ->
                        match read_csv_schema path with
                        | Some cols -> Some cols
                        | None -> None))
          | None -> None
        else None
      in

      (* Determine input schema from dependencies *)
      let input_schema = match dep_of name with
        | [] -> (match root_schema with Some s -> s | None -> [])
        | primary :: _ ->
            (* Use the schema of the primary dependency (the piped-from node) *)
            (try Hashtbl.find schemas primary with Not_found -> [])
      in
      (* Infer output schema *)
      let output_schema = match root_schema with
        | Some cols -> cols
        | None ->
            if List.length ops > 1 then
              List.fold_left apply_pipe_op input_schema ops
            else
              infer_output_schema input_schema expr
      in

      (* Store the schema *)
      if output_schema <> [] then
        Hashtbl.add schemas name output_schema;

      (* Check for type mismatches between input and output schemas *)
      if input_schema <> [] && output_schema <> [] then begin
        let mismatches = List.filter_map (fun in_col ->
          match in_col.sc_type with
          | Some expected_type ->
              (match List.find_opt (fun out_col -> out_col.sc_name = in_col.sc_name) output_schema with
               | Some out_col ->
                   (match out_col.sc_type with
                    | Some actual_type when actual_type <> expected_type ->
                        Some (in_col.sc_name, expected_type, actual_type)
                    | _ -> None)
               | None -> None)
          | None -> None
        ) input_schema in
        List.iter (fun (col_name, expected_type, actual_type) ->
          diagnostics := (Diagnostics.{
            diag_id = Diagnostics.gen_id ();
            diag_error_class = Schema_mismatch;
            diag_severity = Warning;
            diag_phase = Schema;
            diag_node_id = Some name;
            diag_node_lang = None;
            diag_file = Some file;
            diag_line = (match expr.loc with Some l -> Some l.line | None -> None);
            diag_column = (match expr.loc with Some l -> Some l.column | None -> None);
            diag_end_line = None;
            diag_end_column = None;
            diag_message =
              Printf.sprintf "Column '%s' type changed from '%s' to '%s' in node '%s'"
                col_name expected_type actual_type name;
            diag_expected = Some expected_type;
            diag_actual = Some actual_type;
            diag_caused_by = [];
            diag_suggested_fix =
              if List.mem expected_type ["int"; "double"; "string"; "bool"]
              then
                 Diagnostics.make_cast_fix ~column:col_name ~cast_to:expected_type ~chain_broken:current_chain_broken ~target_node:name ?file:(Some file) ?line:(match expr.loc with Some l -> Some l.line | None -> None) ()
              else Diagnostics.no_fix;
          } : Diagnostics.diagnostic) :: !diagnostics
        ) mismatches
      end;

      (* Validate column references in the expression, tracking intermediate
         schemas through pipe chains so that rename() |> select() works correctly. *)
      let all_refs = unwrap_pipe expr in
      let current_validation_schema = ref input_schema in
      (* Note: last_rename_mapping only covers the immediately preceding pipe op.
         A rename earlier in a longer chain (with intervening non-rename ops) will
         still emit a schema_mismatch error, but the suggested_fix will be NoFix
         since the mapping is lost.  The error detection is schema-based and always
         correct; only the automatic fix attachment is affected. *)
      let last_rename_mapping = ref [] in
      List.iter (fun op ->
        let validation_schema =
          if !current_validation_schema <> [] then !current_validation_schema
          else match dep_of name with
            | d :: _ -> (try Hashtbl.find schemas d with Not_found -> [])
            | [] -> []
        in
        if validation_schema <> [] then begin
          let errors = validate_col_refs ~node_name:name ~file:(Some file) ~schema:validation_schema ~rename_mapping:!last_rename_mapping op in
          diagnostics := errors @ !diagnostics
        end;
        last_rename_mapping := extract_rename_mapping op;
        current_validation_schema := apply_pipe_op !current_validation_schema op
      ) all_refs;

      (* Validate expect() contracts: last position validates, mid-chain warns *)
      let ops = unwrap_pipe expr in
      let ops_len = List.length ops in
      let contract_diags = ref [] in
      List.iteri (fun idx op ->
        if classify_verb op = Expect then begin
          if idx <> ops_len - 1 then begin
            (* Mid-chain expect(): warn placement *)
            contract_diags := (Diagnostics.{
              diag_id = gen_id ();
              diag_error_class = Invalid_expect_placement;
              diag_severity = Warning;
              diag_phase = Schema;
              diag_node_id = Some name;
              diag_node_lang = None;
              diag_file = Some file;
              diag_line = (match op.loc with Some l -> Some l.line | None -> None);
              diag_column = None;
              diag_end_line = None;
              diag_end_column = None;
              diag_message = "expect() must be the last step in a pipeline. Contracts from this position will not be validated.";
              diag_expected = None;
              diag_actual = None;
              diag_caused_by = [];
              diag_suggested_fix = Diagnostics.no_fix;
            } : Diagnostics.diagnostic) :: !contract_diags
          end else
            (* Last position: validate contracts against final schema *)
            let contracts = match op.node with
              | Call { args; _ } -> extract_contracts args
              | _ -> []
            in
            let diags = validate_contracts ~node_name:name ~file:(Some file) ~chain_broken:current_chain_broken contracts !current_validation_schema in
            contract_diags := diags @ !contract_diags
        end
      ) ops;
      diagnostics := !contract_diags @ !diagnostics;

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
                    if not (schema_has_col var validation_schema) then
                      Some (Diagnostics.{
                        diag_id = Diagnostics.gen_id ();
                        diag_error_class = Schema_mismatch;
                        diag_severity = Error;
                        diag_phase = Schema;
                        diag_node_id = Some name;
                        diag_node_lang = None;
                        diag_file = Some file;
                        diag_line = (match expr.loc with Some l -> Some l.line | None -> None);
                        diag_column = (match expr.loc with Some l -> Some l.column | None -> None);
                        diag_end_line = None;
                        diag_end_column = None;
                        diag_message = Printf.sprintf "Formula variable '%s' in %s() not found in input schema [%s]"
                          var fn_name (String.concat ", " (schema_names validation_schema));
                        diag_expected = None;
                        diag_actual = None;
                        diag_caused_by = [];
                        diag_suggested_fix = Diagnostics.no_fix;
                      })
                    else None
                  ) all_vars in
                 diagnostics := errors @ !diagnostics
               end
           | None -> ())
      | _ -> ()
    end
  ) topo_order;

  !diagnostics

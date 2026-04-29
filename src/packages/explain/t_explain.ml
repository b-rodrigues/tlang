open Ast

let dataframe_hint =
  "Use explain(df).storage_backend, explain(df).native_path_active, explain(df).performance_note, explain(df).schema, explain(df).na_stats, and explain(df).example_rows for details"

(*
--# Explain Value
--#
--# Returns a dictionary describing the structure and content of a value.
--# Node results from `read_node(...)` are wrapped with node metadata and
--# expose the explained payload under `contents`.
--#
--# @name explain
--# @param x :: Any The value to explain.
--# @return :: Dict A structured description of the value.
--# @example
--#   explain(mtcars)
--#   explain(1)
--# @family explain
--# @seealso type, str
--# @export
*)
let register env =
  let node_passthrough_exclusions =
    ["kind"; "node_name"; "diagnostics"; "contents"; "_display_keys"]
  in
  let rec do_explain v =
    match v with
    | VNodeResult nr ->
        let contents = do_explain nr.v in
        let diagnostics = ("diagnostics", Ast.Utils.node_diagnostics_to_value nr.diagnostics) in
        let node_name = ("node_name", VString nr.node_name) in
        let display_keys =
          ("_display_keys",
           VList [
             (None, VString "kind");
             (None, VString "node_name");
             (None, VString "diagnostics");
             (None, VString "contents");
           ])
        in
        let passthrough_fields =
          match contents with
          | VDict fields ->
              List.filter
                (fun (k, _) ->
                  not (List.mem k node_passthrough_exclusions))
                fields
          | _ -> []
        in
        VDict
          ([
             ("kind", VString "node");
             node_name;
             diagnostics;
             ("contents", contents);
             display_keys;
           ]
           @ passthrough_fields)
    | VInt _ | VFloat _ | VBool _ | VString _ ->
        VDict [
          ("kind", VString "value");
          ("type", VString (Utils.type_name v));
          ("value", v);
        ]
    | VNA na_t ->
        VDict [
          ("kind", VString "value");
          ("type", VString "NA");
          ("na_type", VString (Utils.na_type_to_string na_t));
        ]
    | VVector arr ->
        let len = Array.length arr in
        let type_counts = Hashtbl.create 4 in
        let na_count = ref 0 in
        Array.iter (fun v ->
          let t = Utils.type_name v in
          if t = "NA" then incr na_count
          else begin
            let count = try Hashtbl.find type_counts t with Not_found -> 0 in
            Hashtbl.replace type_counts t (count + 1)
          end
        ) arr;
        let types = Hashtbl.fold (fun k _v acc -> k :: acc) type_counts [] in
        let type_str = String.concat ", " (List.sort String.compare types) in
        let example_n = min 5 len in
        let examples = VList (List.init example_n (fun i -> (None, arr.(i)))) in
        VDict [
          ("kind", VString "value");
          ("type", VString "Vector");
          ("length", VInt len);
          ("element_types", VString type_str);
          ("na_count", VInt !na_count);
          ("examples", examples);
        ]
    | VList items ->
        let len = List.length items in
        let na_count = List.fold_left (fun acc (_, v) ->
          match v with VNA _ -> acc + 1 | _ -> acc
        ) 0 items in
        let example_n = min 5 len in
        let examples = VList (List.filteri (fun i _ -> i < example_n) items) in
        VDict [
          ("kind", VString "value");
          ("type", VString "List");
          ("length", VInt len);
          ("na_count", VInt na_count);
          ("examples", examples);
        ]
    | VDataFrame df ->
        let value_columns = Arrow_bridge.table_to_value_columns df.arrow_table in
        let nrows = Arrow_table.num_rows df.arrow_table in
        let native_path_active = Arrow_table.is_native_backed df.arrow_table in
        let storage_backend =
          if native_path_active then "native_arrow" else "pure_ocaml"
        in
        let performance_note =
          if native_path_active then
            "Native Arrow handle is active; eligible operations can use the vectorized Arrow path."
          else
            "This DataFrame is materialized in OCaml/T storage because native Arrow backing could not be preserved for its current columns or structure."
        in
        let schema = VList (List.map (fun (name, col) ->
          let col_type = ref "Unknown" in
          Array.iter (fun v ->
            if !col_type = "Unknown" then
              match v with VNA _ -> () | _ -> col_type := Utils.type_name v
          ) col;
          (None, VDict [("name", VString name); ("type", VString !col_type)])
        ) value_columns) in
        let na_stats = VDict (List.map (fun (name, col) ->
          let na_count = Array.fold_left (fun acc v ->
            match v with VNA _ -> acc + 1 | _ -> acc
          ) 0 col in
          (name, VInt na_count)
        ) value_columns) in
        let example_n = min 5 nrows in
        let example_rows = VList (List.init example_n (fun i ->
          (None, VDict (Arrow_bridge.row_to_dict df.arrow_table i))
        )) in
        let grouped_info =
          if df.group_keys = [] then []
          else [("group_keys", VList (List.map (fun k -> (None, VString k)) df.group_keys))]
        in
        let display_keys = [
          (None, VString "kind"); (None, VString "nrow"); (None, VString "ncol");
          (None, VString "storage_backend"); (None, VString "native_path_active");
          (None, VString "performance_note"); (None, VString "hint")
        ] @ (if df.group_keys = [] then [] else [(None, VString "group_keys")]) in
        VDict ([
          ("kind", VString "dataframe");
          ("nrow", VInt nrows);
          ("ncol", VInt (Arrow_table.num_columns df.arrow_table));
          ("storage_backend", VString storage_backend);
          ("native_path_active", VBool native_path_active);
          ("performance_note", VString performance_note);
          ("hint", VString dataframe_hint);
          ("schema", schema);
          ("na_stats", na_stats);
          ("example_rows", example_rows);
          ("_display_keys", VList display_keys);
        ] @ grouped_info)
    | VPipeline { p_nodes; p_deps; p_node_diagnostics; _ } ->
        let nodes_info = VList (List.map (fun (name, v) ->
          let deps = match List.assoc_opt name p_deps with
            | Some d -> VList (List.map (fun s -> (None, VString s)) d)
            | None -> VList []
          in
          let diagnostics =
            match List.assoc_opt name p_node_diagnostics with
            | Some diagnostics -> Ast.Utils.node_diagnostics_to_value diagnostics
            | None -> Ast.Utils.node_diagnostics_to_value Ast.Utils.empty_node_diagnostics
          in
          (None, VDict [
            ("name", VString name);
            ("output_kind", VString (Utils.type_name v));
            ("dependencies", deps);
            ("diagnostics", diagnostics);
          ])
        ) p_nodes) in
        VDict [
          ("kind", VString "pipeline");
          ("node_count", VInt (List.length p_nodes));
          ("nodes", nodes_info);
          ("diagnostics", Ast.Utils.pipeline_diagnostics_to_value p_node_diagnostics);
        ]
    | VIntent { intent_fields } ->
        VDict [
          ("kind", VString "intent");
          ("fields", VDict (List.map (fun (k, v) -> (k, VString v)) intent_fields));
        ]
    | VDict pairs ->
        VDict [
          ("kind", VString "value");
          ("type", VString "Dict");
          ("length", VInt (List.length pairs));
          ("keys", VList (List.map (fun (k, _) -> (None, VString k)) pairs));
        ]
    | VError { code; message; context; location; na_count } ->
        let base = [
          ("kind", VString "value");
          ("type", VString "Error");
          ("error_code", VString (Utils.error_code_to_string code));
          ("error_message", VString message);
          ("na_count", VInt na_count);
        ] in
        let loc_fields = 
          match location with
          | Some { file; line; column } ->
              [("file", match file with Some f -> VString f | None -> (VNA NAGeneric));
               ("line", VInt line);
               ("column", VInt column)]
          | None -> []
        in
        VDict (base @ loc_fields @ context)
    | VSymbol s ->
        VDict [
          ("kind", VString "symbol");
          ("name", VString s);
          ("hint", VString "This is a bare symbol/name. It might be an undefined variable or a column reference.");
        ]
    | VFormula { response; predictors; _ } ->
        VDict [
          ("kind", VString "formula");
          ("response", VList (List.map (fun s -> (None, VString s)) response));
          ("predictors", VList (List.map (fun s -> (None, VString s)) predictors));
        ]
    | VBuiltin _ | VLambda _ ->
        VDict [
          ("kind", VString "value");
          ("type", VString "Function");
        ]
    | VComputedNode cn ->
        VDict [
          ("kind", VString "computed_node");
          ("name", VString cn.cn_name);
          ("runtime", VString cn.cn_runtime);
          ("path", VString cn.cn_path);
          ("serializer", VString cn.cn_serializer);
          ("class", VString cn.cn_class);
          ("dependencies", VList (List.map (fun d -> (None, VString d)) cn.cn_dependencies));
        ]
    | VNode un ->
        VDict [
          ("kind", VString "node");
          ("runtime", VString un.un_runtime);
          ("command", VString (Nix_unparse.unparse_expr un.un_command));
          ("noop", VBool un.un_noop);
        ]
    | v ->
        VDict [
          ("kind", VString "value");
          ("type", VString (Utils.type_name v));
          ("hint", VString "Internal structure not exposed for this type.");
        ]
  in
  Env.add "explain"
    (make_builtin ~name:"explain" ~unwrap:false 1 (fun args _env ->
      match args with
      | [v] -> do_explain v
      | _ -> Error.arity_error_named "explain" 1 (List.length args)))
  env

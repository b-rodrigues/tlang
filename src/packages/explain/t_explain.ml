open Ast

let dataframe_hint =
  "Use explain(df).storage_backend, explain(df).native_path_active, explain(df).performance_note, explain(df).schema, explain(df).na_stats, and explain(df).example_rows for details"

let contains_sub s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let rec check i =
      if i + len_sub > len_s then false
      else if String.sub s i len_sub = sub then true
      else check (i + 1)
    in
    check 0

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
  (* Fields that belong to the outer node wrapper and should therefore be
     excluded from passthrough when copying non-conflicting payload fields. *)
  let passthrough_exclusions =
    ["kind"; "node_name"; "diagnostics"; "contents"; "_display_keys"]
  in
  let make_display_keys keys =
    VList (List.map (fun key -> (None, VString key)) keys)
  in
  let make_explain_dict ?display_keys fields =
    let keys =
      match display_keys with
      | Some keys -> keys
      | None -> List.map fst fields
    in
    VDict (fields @ [("_display_keys", make_display_keys keys)])
  in
  let rec do_explain v =
    match v with
    | VNodeResult nr ->
        let contents = do_explain nr.v in
        let diagnostics = ("diagnostics", Ast.Utils.node_diagnostics_to_value nr.diagnostics) in
        let node_name = ("node_name", VString nr.node_name) in
        let passthrough_fields =
          match contents with
          | VDict fields ->
              List.filter
                (fun (k, _) ->
                  not (List.mem k passthrough_exclusions))
                fields
          | _ -> []
        in
        make_explain_dict
          ~display_keys:["kind"; "node_name"; "diagnostics"; "contents"]
          ([
             ("kind", VString "node");
             node_name;
             diagnostics;
             ("contents", contents);
           ]
           @ passthrough_fields)
    | VInt _ | VFloat _ | VBool _ | VString _ ->
        make_explain_dict [
          ("kind", VString "value");
          ("type", VString (Utils.type_name v));
          ("value", v);
        ]
    | VNA na_t ->
        make_explain_dict [
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
        make_explain_dict [
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
        make_explain_dict [
          ("kind", VString "value");
          ("type", VString "List");
          ("length", VInt len);
          ("na_count", VInt na_count);
          ("examples", examples);
        ]
    | VDataFrame df ->
        let value_columns = Arrow_bridge.table_to_value_columns df.arrow_table in
        let nrows = Arrow_table.num_rows df.arrow_table in
        let is_collect_exceptions_df =
          match List.map fst value_columns with
          | ["node"; "status"; "code"; "message"] -> true
          | _ -> false
        in
        if is_collect_exceptions_df then
          let node_col = List.assoc "node" value_columns in
          let status_col = List.assoc "status" value_columns in
          let code_col = List.assoc "code" value_columns in
          let message_col = List.assoc "message" value_columns in
          let get_str_val col row =
            match col.(row) with
            | VString s -> s
            | _ -> ""
          in
          let explain_exception_row node_val status_val code_val message_val =
            if status_val = "Error" then
              make_explain_dict [
                ("kind", VString "value");
                ("type", VString "Error");
                ("error_code", VString code_val);
                ("error_message", VString message_val);
                ("node", VString node_val);
              ]
            else
              make_explain_dict [
                ("kind", VString "value");
                ("type", VString "Warning");
                ("warning_code", VString code_val);
                ("warning_message", VString message_val);
                ("node", VString node_val);
              ]
          in
          if nrows = 1 then
            let node_val = get_str_val node_col 0 in
            let status_val = get_str_val status_col 0 in
            let code_val = get_str_val code_col 0 in
            let message_val = get_str_val message_col 0 in
            explain_exception_row node_val status_val code_val message_val
          else
            let elements = List.init nrows (fun i ->
              let node_val = get_str_val node_col i in
              let status_val = get_str_val status_col i in
              let code_val = get_str_val code_col i in
              let message_val = get_str_val message_col i in
              (None, explain_exception_row node_val status_val code_val message_val)
            ) in
            make_explain_dict [
              ("kind", VString "exceptions_list");
              ("type", VString "exceptions_list");
              ("description", VString "A list of exceptions and warnings captured from the pipeline build.");
              ("count", VInt nrows);
              ("exceptions", VList elements);
            ]
        else
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
        let display_key_names = [
          "kind"; "nrow"; "ncol";
          "storage_backend"; "native_path_active";
          "performance_note"; "hint"
        ] @ (if df.group_keys = [] then [] else ["group_keys"]) in
        make_explain_dict
          ~display_keys:display_key_names
          ([
             ("kind", VString "to_dataframe");
             ("nrow", VInt nrows);
             ("ncol", VInt (Arrow_table.num_columns df.arrow_table));
             ("storage_backend", VString storage_backend);
             ("native_path_active", VBool native_path_active);
             ("performance_note", VString performance_note);
             ("hint", VString dataframe_hint);
             ("schema", schema);
             ("na_stats", na_stats);
             ("example_rows", example_rows);
           ] @ grouped_info)
    | VPipeline ({ p_deps; _ } as pipeline) ->
        let p_nodes =
          Builder.merge_pipeline_nodes_with_latest_log pipeline
        in
        let p_node_diagnostics =
          Builder.merge_pipeline_node_diagnostics_with_latest_log pipeline
        in
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
        make_explain_dict [
          ("kind", VString "pipeline");
          ("node_count", VInt (List.length p_nodes));
          ("nodes", nodes_info);
          ("diagnostics", Ast.Utils.pipeline_diagnostics_to_value p_node_diagnostics);
        ]
    | VIntent { intent_fields } ->
        make_explain_dict [
          ("kind", VString "intent");
          ("fields", VDict (List.map (fun (k, v) -> (k, VString v)) intent_fields));
        ]
    | VDict pairs when List.mem_assoc "kind" pairs
                      && (match List.assoc_opt "kind" pairs with
                          | Some (VString k) -> k = "dataframe_diff" || k = "model_diff"
                                                || k = "scalar_diff" || k = "generic_diff"
                                                || k = "pipeline_diff"
                          | _ -> false) ->
        (* VDiff envelope — explain renders a structured summary *)
        let get_str k = match List.assoc_opt k pairs with Some (VString s) -> s | _ -> "" in
        let get_bool k = match List.assoc_opt k pairs with Some (VBool b) -> b | _ -> false in
        let kind = get_str "kind" in
        let identical = get_bool "identical" in
        if kind = "pipeline_diff" then
          let rewired_count = match List.assoc_opt "rewired_edges" pairs with Some (VList items) -> List.length items | _ -> 0 in
          make_explain_dict
            ~display_keys:["kind"; "identical"; "added_nodes"; "removed_nodes"; "changed_nodes"; "rewired_edges"]
            [
              ("kind", VString "VDiff (pipeline_diff)");
              ("identical", VBool identical);
              ("added_nodes", match List.assoc_opt "added_nodes" pairs with Some v -> v | None -> VList []);
              ("removed_nodes", match List.assoc_opt "removed_nodes" pairs with Some v -> v | None -> VList []);
              ("changed_nodes", match List.assoc_opt "changed_nodes" pairs with Some v -> v | None -> VList []);
              ("rewired_edges", VInt rewired_count);
            ]
        else
          let node_a = get_str "node_a" in
          let node_b = get_str "node_b" in
          let log_a = get_str "log_a" in
          let log_b = get_str "log_b" in
          let value_type = get_str "value_type" in
          let summary = match List.assoc_opt "summary" pairs with Some v -> v | None -> VNA NAGeneric in
          let hunks = match List.assoc_opt "hunks" pairs with Some (VList h) -> List.length h | _ -> 0 in
          make_explain_dict
            ~display_keys:["kind"; "nodes"; "builds"; "value_type"; "identical"; "summary"; "hunks_count"]
            [
              ("kind", VString ("VDiff (" ^ kind ^ ")"));
              ("nodes", VString (node_a ^ " → " ^ node_b));
              ("builds", VString (log_a ^ " → " ^ log_b));
              ("value_type", VString value_type);
              ("identical", VBool identical);
              ("summary", summary);
              ("hunks_count", VInt hunks);
            ]
    | VDict pairs ->
        make_explain_dict [
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
        make_explain_dict (base @ loc_fields @ context)
    | VSymbol s ->
        make_explain_dict [
          ("kind", VString "symbol");
          ("name", VString s);
          ("hint", VString "This is a bare symbol/name. It might be an undefined variable or a column reference.");
        ]
    | VFormula { response; predictors; _ } ->
        make_explain_dict [
          ("kind", VString "formula");
          ("response", VList (List.map (fun s -> (None, VString s)) response));
          ("predictors", VList (List.map (fun s -> (None, VString s)) predictors));
        ]
    | VLambda l ->
        let rec zip params param_types =
          match params, param_types with
          | p :: ps, pt :: pts ->
              let type_str =
                match pt with
                | Some t -> Ast.Utils.typ_to_string t
                | None -> "Any"
              in
              let arg_dict = make_explain_dict [
                ("name", VString p);
                ("type", VString type_str);
                ("default", VNA NAGeneric);
              ] in
              (None, arg_dict) :: zip ps pts
          | p :: ps, [] ->
              let arg_dict = make_explain_dict [
                ("name", VString p);
                ("type", VString "Any");
                ("default", VNA NAGeneric);
              ] in
              (None, arg_dict) :: zip ps []
          | [], _ -> []
        in
        let arguments = VList (zip l.params l.param_types) in
        make_explain_dict [
          ("kind", VString "value");
          ("type", VString "Function");
          ("arguments", arguments);
        ]
    | VBuiltin b ->
        let rec map_params params =
          match params with
          | (p : Tdoc_types.param_doc) :: ps ->
              let type_str = match p.Tdoc_types.type_info with Some t -> t | None -> "Any" in
              let default_str =
                let text = String.lowercase_ascii (type_str ^ " " ^ p.Tdoc_types.description) in
                if contains_sub text "optional" || contains_sub text "default = na" then
                  VString "NA"
                else if contains_sub text "default =" then
                  match String.split_on_char '=' text with
                  | _ :: right :: _ ->
                      let cleaned = String.trim (List.hd (String.split_on_char ' ' (String.trim right))) in
                      VString cleaned
                  | _ -> VNA NAGeneric
                else if contains_sub text "defaults to" then
                  VString "NA"
                else
                  VNA NAGeneric
              in
              let arg_dict = make_explain_dict [
                ("name", VString p.Tdoc_types.name);
                ("type", VString type_str);
                ("default", default_str);
              ] in
              (None, arg_dict) :: map_params ps
          | [] -> []
        in
        let arguments =
          match b.b_name with
          | Some name ->
              (match Tdoc_registry.lookup name with
               | Some doc -> VList (map_params doc.Tdoc_types.params)
               | None ->
                   let args_list = List.init b.b_arity (fun i ->
                     let name = Printf.sprintf "arg%d" (i + 1) in
                     (None, make_explain_dict [
                       ("name", VString name);
                       ("type", VString "Any");
                       ("default", VNA NAGeneric);
                     ])
                   ) in
                   VList args_list)
          | None ->
              let args_list = List.init b.b_arity (fun i ->
                let name = Printf.sprintf "arg%d" (i + 1) in
                (None, make_explain_dict [
                  ("name", VString name);
                  ("type", VString "Any");
                  ("default", VNA NAGeneric);
                ])
              ) in
              VList args_list
        in
        make_explain_dict [
          ("kind", VString "value");
          ("type", VString "Function");
          ("arguments", arguments);
        ]
    | VComputedNode cn ->
        let cn = !Ast.computed_node_resolver cn in
        make_explain_dict [
          ("kind", VString "computed_node");
          ("name", VString cn.cn_name);
          ("runtime", VString cn.cn_runtime);
          ("path", VString cn.cn_path);
          ("serializer", VString cn.cn_serializer);
          ("class", VString cn.cn_class);
          ("dependencies", VList (List.map (fun d -> (None, VString d)) cn.cn_dependencies));
        ]
    | VNode un ->
        make_explain_dict [
          ("kind", VString "node");
          ("runtime", VString un.un_runtime);
          ("command", VString (Nix_unparse.unparse_expr un.un_command));
          ("noop", VBool un.un_noop);
        ]
    | v ->
        make_explain_dict [
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

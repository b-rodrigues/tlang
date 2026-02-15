open Ast

(*
--# Explain Value
--#
--# Returns a dictionary describing the structure and content of a value.
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
  Env.add "explain"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VInt _] | [VFloat _] | [VBool _] | [VString _] ->
          let v = List.hd args in
          VDict [
            ("kind", VString "value");
            ("type", VString (Utils.type_name v));
            ("value", v);
          ]
      | [VNA na_t] ->
          VDict [
            ("kind", VString "value");
            ("type", VString "NA");
            ("na_type", VString (Utils.na_type_to_string na_t));
          ]
      | [VVector arr] ->
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
      | [VList items] ->
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
      | [VDataFrame df] ->
          let value_columns = Arrow_bridge.table_to_value_columns df.arrow_table in
          let nrows = Arrow_table.num_rows df.arrow_table in
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
            (None, VString "hint")
          ] @ (if df.group_keys = [] then [] else [(None, VString "group_keys")]) in
          VDict ([
            ("kind", VString "dataframe");
            ("nrow", VInt nrows);
            ("ncol", VInt (Arrow_table.num_columns df.arrow_table));
            ("hint", VString "Use explain(df).schema, explain(df).na_stats, explain(df).example_rows for details");
            ("schema", schema);
            ("na_stats", na_stats);
            ("example_rows", example_rows);
            ("_display_keys", VList display_keys);
          ] @ grouped_info)
      | [VPipeline { p_nodes; p_deps; _ }] ->
          let nodes_info = VList (List.map (fun (name, v) ->
            let deps = match List.assoc_opt name p_deps with
              | Some d -> VList (List.map (fun s -> (None, VString s)) d)
              | None -> VList []
            in
            (None, VDict [
              ("name", VString name);
              ("output_kind", VString (Utils.type_name v));
              ("dependencies", deps);
            ])
          ) p_nodes) in
          VDict [
            ("kind", VString "pipeline");
            ("node_count", VInt (List.length p_nodes));
            ("nodes", nodes_info);
          ]
      | [VIntent { intent_fields }] ->
          VDict [
            ("kind", VString "intent");
            ("fields", VDict (List.map (fun (k, v) -> (k, VString v)) intent_fields));
          ]
      | [VDict pairs] ->
          VDict [
            ("kind", VString "value");
            ("type", VString "Dict");
            ("length", VInt (List.length pairs));
            ("keys", VList (List.map (fun (k, _) -> (None, VString k)) pairs));
          ]
      | [VNull] ->
          VDict [
            ("kind", VString "value");
            ("type", VString "Null");
          ]
      | [VError { code; message; _ }] ->
          VDict [
            ("kind", VString "value");
            ("type", VString "Error");
            ("error_code", VString (Utils.error_code_to_string code));
            ("error_message", VString message);
          ]
      | [VLambda _] | [VBuiltin _] ->
          VDict [
            ("kind", VString "value");
            ("type", VString "Function");
          ]
      | _ -> Error.arity_error_named "explain" ~expected:1 ~received:(List.length args)
    ))
    env

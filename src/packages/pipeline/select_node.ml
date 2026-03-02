open Ast

(*
--# Select Node Metadata Fields
--#
--# Returns a DataFrame summarising the requested metadata fields for all
--# nodes in the pipeline. This is a read-only inspection operation — it does
--# not return a Pipeline.
--#
--# Available fields: `$name`, `$runtime`, `$serializer`, `$deserializer`,
--# `$noop`, `$deps`, `$depth`, `$command_type`.
--#
--# @name select_node
--# @param p :: Pipeline The pipeline to inspect.
--# @param ... :: Symbol One or more metadata field references (e.g. `$name`, `$runtime`).
--# @return :: DataFrame A DataFrame with the requested metadata columns.
--# @example
--#   p |> select_node($name, $runtime, $deps)
--#   p |> select_node($name, $depth, $noop)
--# @family pipeline
--# @seealso pipeline_to_frame, filter_node, arrange_node
--# @export
*)

let all_metadata_fields =
  ["name"; "runtime"; "serializer"; "deserializer"; "noop"; "deps"; "depth"; "command_type"]

let register env =
  Env.add "select_node"
    (make_builtin ~name:"select_node" ~variadic:true 1 (fun args _env ->
      match args with
      | VPipeline p :: col_args when col_args <> [] ->
          let col_names = List.filter_map Utils.extract_column_name col_args in
          if List.length col_names <> List.length col_args then
            Error.type_error "Function `select_node` expects `$field` column references."
          else
            let missing = List.filter (fun c -> not (List.mem c all_metadata_fields)) col_names in
            if missing <> [] then
              Error.make_error KeyError
                (Printf.sprintf "Unknown node metadata field(s): %s. Available: %s."
                   (String.concat ", " missing)
                   (String.concat ", " all_metadata_fields))
            else
              (* Build the full frame and project the requested columns *)
              let depths = Pipeline_to_frame.compute_depths p.p_deps in
              let node_names = List.map fst p.p_exprs in
              let nrows = List.length node_names in
              (* Helper to build a column by extracting a field from each node's metadata dict *)
              let get_field field_name =
                Array.init nrows (fun i ->
                  let n = List.nth node_names i in
                  let meta = Pipeline_to_frame.node_metadata_dict n p depths in
                  match List.assoc_opt field_name meta with
                  | Some (VList items) ->
                      (* Render dep lists as comma-separated strings *)
                      let strs = List.filter_map (fun (_, v) ->
                        match v with VString s -> Some s | _ -> None
                      ) items in
                      Some (String.concat ", " strs)
                  | Some v -> Some (Utils.value_to_raw_string v)
                  | None -> None
                )
              in
              let get_int_field field_name =
                Array.init nrows (fun i ->
                  let n = List.nth node_names i in
                  let meta = Pipeline_to_frame.node_metadata_dict n p depths in
                  match List.assoc_opt field_name meta with
                  | Some (VInt v) -> Some v
                  | _ -> None
                )
              in
              let get_bool_field field_name =
                Array.init nrows (fun i ->
                  let n = List.nth node_names i in
                  let meta = Pipeline_to_frame.node_metadata_dict n p depths in
                  match List.assoc_opt field_name meta with
                  | Some (VBool v) -> Some v
                  | _ -> None
                )
              in
              let columns = List.filter_map (fun col ->
                match col with
                | "noop"  -> Some (col, Arrow_table.BoolColumn (get_bool_field col))
                | "depth" -> Some (col, Arrow_table.IntColumn (get_int_field col))
                | _       -> Some (col, Arrow_table.StringColumn (get_field col))
              ) col_names in
              let arrow_table = Arrow_table.create columns nrows in
              VDataFrame { arrow_table; group_keys = [] }
      | [VPipeline _] ->
          Error.make_error ArityError
            "Function `select_node` requires at least one `$field` argument."
      | _ :: _ -> Error.type_error "Function `select_node` expects a Pipeline as first argument."
      | [] -> Error.arity_error_named "select_node" ~expected:1 ~received:0
    ))
    env


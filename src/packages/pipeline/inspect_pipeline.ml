open Ast

(*
--# Inspect Pipeline Schema (Static)
--#
--# Returns a DataFrame outlining the static compile-time configuration of the pipeline.
--#
--# @name inspect_pipeline
--# @param p :: Pipeline The pipeline to inspect statically.
--# @return :: DataFrame A DataFrame with columns = node, runtime, serializer, dependencies, has_script.
--# @family pipeline
--# @export
*)
let register env =
  let inspect_fn named_args _env =
    let extract_arg name pos default args =
      match List.assoc_opt (Some name) args with
      | Some v -> v
      | None ->
          let positionals = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
          if List.length positionals >= pos then List.nth positionals (pos - 1)
          else default
    in
    match extract_arg "p" 1 (VNA NAGeneric) named_args with
    | VPipeline p ->
        let nodes_list = p.p_nodes in
        let nrows = List.length nodes_list in
        let arr_nodes = Array.init nrows (fun i -> let (name, _) = List.nth nodes_list i in Some name) in
        let arr_runtimes = Array.init nrows (fun i ->
          let (name, _) = List.nth nodes_list i in
          Some (match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "Unknown")
        ) in
        let arr_serializers = Array.init nrows (fun i ->
          let (name, _) = List.nth nodes_list i in
          Some (match List.assoc_opt name p.p_serializers with
                | Some expr -> Nix_unparse.unparse_expr expr
                | None -> "Unknown")
        ) in
        let arr_dependencies = Array.init nrows (fun i ->
          let (name, _) = List.nth nodes_list i in
          let deps = match List.assoc_opt name p.p_deps with Some ds -> ds | None -> [] in
          Some (String.concat ", " deps)
        ) in
        let arr_has_script = Array.init nrows (fun i ->
          let (name, _) = List.nth nodes_list i in
          let has_sc = match List.assoc_opt name p.p_scripts with Some (Some _) -> true | _ -> false in
          Some has_sc
        ) in
        let columns = [
          ("node", Arrow_table.StringColumn arr_nodes);
          ("runtime", Arrow_table.StringColumn arr_runtimes);
          ("serializer", Arrow_table.StringColumn arr_serializers);
          ("dependencies", Arrow_table.StringColumn arr_dependencies);
          ("has_script", Arrow_table.BoolColumn arr_has_script);
        ] in
        let arrow_table = Arrow_table.create columns nrows in
        VDataFrame { arrow_table; group_keys = [] }
    | other ->
        Error.type_error (Printf.sprintf "inspect_pipeline: expected a Pipeline, but got %s." (Utils.type_name other))
  in
  let env = Env.add "inspect_pipeline" (make_builtin_named ~name:"inspect_pipeline" ~variadic:true 1 inspect_fn) env in

  (*
  --# List Pipeline Logs
  --#
  --# Lists all available build logs in the `_pipeline/` directory.
  --#
  --# @name list_logs
  --# @return :: DataFrame A DataFrame of build log files with their modification times and sizes.
  --# @family pipeline
  --# @export
  *)
  let env = Env.add "list_logs" (make_builtin ~name:"list_logs" 0 (fun _args _env -> Builder.list_logs ())) env in
  
  (*
  --# Read Node Build Log
  --#
  --# Fetches the Nix build log for a specific node from the last build attempt.
  --#
  --# @name read_log
  --# @param node_name :: String The name of the node to inspect.
  --# @return :: String The build log content.
  --# @family pipeline
  --# @export
  *)
  let env = Env.add "read_log" (make_builtin ~name:"read_log" 1 (fun args _env -> 
    match args with
    | [VString s] | [VSymbol s] -> Builder.read_node_log s
    | _ -> Error.type_error "read_log: expected a String or Symbol node name"
  )) env in
  env

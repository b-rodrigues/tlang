open Ast

(*
--# Check Pipeline Cache Status
--#
--# Queries local Nix store validity for each node in a pipeline.
--#
--# @name pipeline_cache_status
--# @param p :: Pipeline The pipeline to inspect.
--# @return :: DataFrame A DataFrame with columns `node` (String), `cached` (Bool), and `store_path` (String).
--# @example
--#   pipeline_cache_status(p)
--# @family pipeline
--# @export
*)
let register env =
  Env.add "pipeline_cache_status"
    (make_builtin ~name:"pipeline_cache_status" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          (match Builder.populate_pipeline ~build:false p with
           | Error msg -> Error.make_error StructuralError msg
           | Ok _ ->
               let node_names = List.map fst p.p_nodes in
               let nrows = List.length node_names in
               let arr_node = Array.init nrows (fun i -> Some (List.nth node_names i)) in
               let arr_cached = Array.make nrows (Some false) in
               let arr_store_path = Array.make nrows None in

               let err_opt = ref None in
               List.iteri (fun i name ->
                 if !err_opt = None then (
                   match Builder_utils.eval_node_store_path name with
                   | Error err -> err_opt := Some err
                   | Ok store_path ->
                       arr_store_path.(i) <- Some store_path;
                       let check_argv = [| "nix-store"; "--query"; "--valid"; store_path |] in
                       let cached =
                         match Builder_utils.run_command_argv_exit check_argv with
                         | Ok 0 -> true
                         | _ -> false
                       in
                       arr_cached.(i) <- Some cached
                 )
               ) node_names;

               match !err_opt with
               | Some err -> err
               | None ->
                   let columns = [
                     ("node",       Arrow_table.StringColumn arr_node);
                     ("cached",     Arrow_table.BoolColumn arr_cached);
                     ("store_path", Arrow_table.StringColumn arr_store_path);
                   ] in
                   let arrow_table = Arrow_table.create columns nrows in
                   VDataFrame { arrow_table; group_keys = [] })
      | [_] -> Error.type_error "Function `pipeline_cache_status` expects a Pipeline as argument."
      | _ -> Error.arity_error_named "pipeline_cache_status" 1 (List.length args)
    ))
    env

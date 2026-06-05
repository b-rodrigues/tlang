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
                let results =
                  let rec go acc = function
                    | [] -> Ok (List.rev acc)
                    | name :: rest ->
                        (match Builder_utils.eval_node_store_path name with
                         | Error err -> Error err
                         | Ok store_path ->
                             let check_argv = [| "nix-store"; "--verify-path"; store_path |] in
                             let cached =
                               match Builder_utils.run_command_argv_exit check_argv with
                               | Ok 0 -> true
                               | _ -> false
                             in
                             go ((name, cached, store_path) :: acc) rest)
                  in
                  go [] node_names
                in
                (match results with
                 | Error err -> err
                 | Ok entries ->
                     let entries_arr = Array.of_list entries in
                     let nrows = Array.length entries_arr in
                     let arr_node = Array.init nrows (fun i -> let (name, _, _) = entries_arr.(i) in Some name) in
                     let arr_cached = Array.init nrows (fun i -> let (_, cached, _) = entries_arr.(i) in Some cached) in
                     let arr_store_path = Array.init nrows (fun i -> let (_, _, sp) = entries_arr.(i) in Some sp) in
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

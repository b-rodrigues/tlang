open Ast

(*
--# Check Pipeline Cache Status
--#
--# Queries Nix cache validity for each node in a pipeline.
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
               let strip_quotes s =
                 let len = String.length s in
                 if len >= 2 && s.[0] = '"' && s.[len - 1] = '"' then
                   String.sub s 1 (len - 2)
                 else
                   s
               in
               let node_names = List.map fst p.p_nodes in
               let nrows = List.length node_names in
               let arr_node = Array.init nrows (fun i -> Some (List.nth node_names i)) in
               let arr_cached = Array.make nrows (Some false) in
               let arr_store_path = Array.make nrows None in

               let err_opt = ref None in
               List.iteri (fun i name ->
                 if !err_opt = None then (
                   let expr = Printf.sprintf "(import %s {}).%s.outPath" (Filename.quote Builder_utils.pipeline_nix_path) name in
                   let argv = [| "nix-instantiate"; "--eval"; "--impure"; "--json"; "-E"; expr |] in
                   match Builder_utils.run_command_argv_capture argv with
                   | Error msg ->
                       err_opt := Some (Error.make_error RuntimeError
                         (Printf.sprintf "pipeline_cache_status: `nix-instantiate` failed for node '%s': %s" name msg))
                   | Ok "" ->
                       err_opt := Some (Error.make_error RuntimeError
                         (Printf.sprintf "pipeline_cache_status: `nix-instantiate` returned empty output for node '%s'" name))
                   | Ok res ->
                       let store_path = strip_quotes res in
                       arr_store_path.(i) <- Some store_path;
                       let check_argv = [| "nix"; "path-info"; store_path |] in
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

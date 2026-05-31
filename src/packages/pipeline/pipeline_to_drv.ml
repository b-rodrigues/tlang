open Ast

(*
--# Introspect Node Derivation Paths
--#
--# Returns a dictionary mapping each node name to its low-level Nix store derivation (.drv) path.
--#
--# @name pipeline_to_drv
--# @param p :: Pipeline The pipeline.
--# @return :: Dict A dictionary of [node_name: drv_path] strings.
--# @example
--#   p = pipeline {
--#     a = 1
--#   }
--#   pipeline_to_drv(p)
--# @family pipeline
--# @export
*)
let register env =
  Env.add "pipeline_to_drv"
    (make_builtin ~name:"pipeline_to_drv" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          (match Builder.populate_pipeline ~build:false p with
           | Error msg -> Error.make_error StructuralError msg
           | Ok _ ->
               let drv_pairs =
                 List.map (fun (name, _) ->
                   let argv = [| "nix-instantiate"; "--impure"; Builder_utils.pipeline_nix_path; "-A"; name |] in
                   let v = match Builder_utils.run_command_argv_capture argv with
                     | Error msg ->
                         Error.make_error RuntimeError
                           (Printf.sprintf "pipeline_to_drv: `nix-instantiate` failed for node '%s': %s" name msg)
                     | Ok "" ->
                         Error.make_error RuntimeError
                           (Printf.sprintf "pipeline_to_drv: `nix-instantiate` returned empty output for node '%s'" name)
                     | Ok drv_path ->
                         VString (String.trim drv_path)
                   in
                   (name, v)
                 ) p.p_nodes
               in
               VDict drv_pairs)
      | [_] -> Error.type_error "Function `pipeline_to_drv` expects a Pipeline as argument."
      | _ -> Error.arity_error_named "pipeline_to_drv" 1 (List.length args)
    ))
    env

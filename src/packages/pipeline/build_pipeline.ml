open Ast

(*
--# Build Pipeline Artifacts
--#
--# Builds a pipeline to `pipeline.nix` and records node artifacts in a local registry.
--#
--# @name build_pipeline
--# @param p :: Pipeline The pipeline to build.
--# @return :: String The output path (Nix store path or local fallback directory).
--# @family pipeline
--# @seealso read_node
--# @export
*)
let register env =
  Env.add "build_pipeline"
    (make_builtin ~name:"build_pipeline" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          let has_errors = List.exists (fun (_, v) -> is_error_value v) p.p_nodes in
          if has_errors then
            Error.value_error ("Cannot build pipeline with errors: " ^ (Utils.value_to_string (VPipeline p)))
          else
            (match Builder.populate_pipeline ~build:true p with
            | Ok out_path -> VString out_path
            | Error msg -> Error.make_error FileError msg)
      | [_] -> Error.type_error "Function `build_pipeline` expects a Pipeline."
      | _ -> Error.arity_error_named "build_pipeline" ~expected:1 ~received:(List.length args)
    ))
    env

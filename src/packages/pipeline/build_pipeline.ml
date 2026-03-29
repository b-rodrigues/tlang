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
let register ~rerun_pipeline env =
  Env.add "build_pipeline"
    (make_builtin ~name:"build_pipeline" 1 (fun args env ->
      match args with
      | [VPipeline p] ->
          (* Trigger a final resolution pass to catch typos or unresolved cross-pipeline deps *)
          let p_resolved = (match rerun_pipeline ?strict:(Some true) env p with VPipeline p' -> p' | other -> failwith (Utils.value_to_string other)) in
          let has_errors = List.exists (fun (_, v) -> is_error_value v) p_resolved.p_nodes in
          if has_errors then
            Error.value_error ("Cannot build pipeline with errors: " ^ (Utils.value_to_string (VPipeline p_resolved)))
          else
            (match Builder.populate_pipeline ~build:true p_resolved with
            | Ok out_path -> VString out_path
            | Error msg -> Error.make_error FileError msg)
      | [_] -> Error.type_error "Function `build_pipeline` expects a Pipeline."
      | _ -> Error.arity_error_named "build_pipeline" 1 (List.length args)
    ))
    env

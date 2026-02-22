(* src/pipeline/builder_populate.ml *)
open Builder_utils
open Builder_write_dag
open Builder_nix_store
open Builder_internal

let populate_pipeline ?(build=false) (p : Ast.pipeline_result) =
  ensure_pipeline_dir ();
  write_env_nix ();
  match write_dag p with
  | Error msg -> Error ("Failed to write dag.json: " ^ msg)
  | Ok () ->
      let nix_content = Nix_emitter.emit_pipeline p in
      match write_file pipeline_nix_path nix_content with
      | Error msg -> Error ("Failed to write pipeline.nix: " ^ msg)
      | Ok () ->
          if build then build_pipeline_internal p
          else Ok (Printf.sprintf "Pipeline populated in `%s`" pipeline_dir)

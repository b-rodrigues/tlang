open Ast

(*
--# Introspect Node Store Paths
--#
--# Returns a dictionary mapping each node name to its low-level Nix store output path.
--#
--# @name pipeline_to_store
--# @param p :: Pipeline The pipeline.
--# @return :: Dict A dictionary of [node_name: store_path] strings.
--# @example
--#   p = pipeline {
--#     a = 1
--#   }
--#   pipeline_to_store(p)
--# @family pipeline
--# @export
*)
let register env =
  Env.add "pipeline_to_store"
    (make_builtin ~name:"pipeline_to_store" 1 (fun args _env ->
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
               let store_pairs =
                 List.map (fun (name, _) ->
                   let expr = Printf.sprintf "(import %s {}).%s.outPath" (Filename.quote Builder_utils.pipeline_nix_path) name in
                   let argv = [| "nix-instantiate"; "--eval"; "--impure"; "--json"; "-E"; expr |] in
                   let v = match Builder_utils.run_command_argv_capture argv with
                     | Error msg ->
                         Error.make_error RuntimeError
                           (Printf.sprintf "pipeline_to_store: `nix-instantiate` failed for node '%s': %s" name msg)
                     | Ok "" ->
                         Error.make_error RuntimeError
                           (Printf.sprintf "pipeline_to_store: `nix-instantiate` returned empty output for node '%s'" name)
                     | Ok res ->
                         VString (strip_quotes res)
                   in
                   (name, v)
                 ) p.p_nodes
               in
               VDict store_pairs)
      | [_] -> Error.type_error "Function `pipeline_to_store` expects a Pipeline as argument."
      | _ -> Error.arity_error_named "pipeline_to_store" 1 (List.length args)
    ))
    env

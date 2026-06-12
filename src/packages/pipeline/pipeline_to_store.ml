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
               let store_pairs =
                 List.map (fun (name, _) ->
                   let v =
                     match Builder_utils.eval_node_store_path name with
                     | Ok path -> VString path
                     | Error err -> err
                   in
                   (name, v)
                 ) p.p_nodes
               in
               VDict store_pairs)
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_to_store` expects a Pipeline, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "pipeline_to_store" 1 (List.length args)
    ))
    env

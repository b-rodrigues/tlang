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
                   let cmd = Printf.sprintf "nix-instantiate --impure _pipeline/pipeline.nix -A %s 2>/dev/null" name in
                   let ic = Unix.open_process_in cmd in
                   let line = try String.trim (input_line ic) with _ -> "" in
                   ignore (Unix.close_process_in ic);
                   (name, VString line)
                 ) p.p_nodes
               in
               VDict drv_pairs)
      | [_] -> Error.type_error "Function `pipeline_to_drv` expects a Pipeline as argument."
      | _ -> Error.arity_error_named "pipeline_to_drv" 1 (List.length args)
    ))
    env

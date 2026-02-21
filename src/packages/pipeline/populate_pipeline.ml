open Ast

(*
--# Populate Pipeline
--#
--# Generates the `_pipeline/` directory with `pipeline.nix` and `dag.json`.
--# Optionally builds the pipeline.
--#
--# @name populate_pipeline
--# @param p :: Pipeline The pipeline to populate.
--# @param build :: Bool (Optional) Whether to trigger the Nix build immediately. Defaults to false.
--# @return :: String A status message or the output path if build=true.
--# @family pipeline
--# @export
*)
let register env =
  let populate_fn named_args _env =
    let p = match List.assoc_opt "p" (List.map (fun (k, v) -> (match k with Some s -> s | None -> "p"), v) named_args) with
      | Some (VPipeline p) -> p
      | _ -> (match List.hd named_args with (_, VPipeline p) -> p | _ -> failwith "Expected Pipeline")
    in
    let build = match List.assoc_opt "build" (List.map (fun (k, v) -> (match k with Some s -> s | None -> "build"), v) named_args) with
      | Some (VBool b) -> b
      | _ -> false
    in
    match Builder.populate_pipeline ~build p with
    | Ok out -> VString out
    | Error msg -> Error.make_error FileError msg
  in
  Env.add "populate_pipeline" (make_builtin_named ~name:"populate_pipeline" 2 populate_fn) env

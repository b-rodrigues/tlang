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
    let get_arg name pos default named_args =
      match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
      | Some v -> v
      | None ->
          let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
          if List.length positionals >= pos then List.nth positionals (pos - 1)
          else default
    in
    let p = match get_arg "p" 1 VNull named_args with
      | VPipeline p -> p
      | _ -> failwith "Expected Pipeline"
    in
    let build = match get_arg "build" 2 (VBool false) named_args with
      | VBool b -> b
      | _ -> false
    in
    match Builder.populate_pipeline ~build p with
    | Ok out -> VString out
    | Error msg -> Error.make_error FileError msg
  in
  Env.add "populate_pipeline" (make_builtin_named ~name:"populate_pipeline" ~variadic:true 1 populate_fn) env

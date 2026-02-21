open Ast

(*
--# Read Pipeline Node Artifact
--#
--# Reads a node artifact from the latest (or specified) build log in `_pipeline/`.
--# Use `which_log` to read from a specific historical build ("time travel").
--#
--# @name read_node
--# @param name :: String The node name.
--# @param which_log :: String (Optional) A regex pattern to match a specific build log filename.
--# @return :: Any The deserialized value.
--# @family pipeline
--# @seealso build_pipeline, load_node, inspect_pipeline
--# @export
*)
let register env =
  let read_fn named_args _env =
    let name = match List.assoc_opt "name" (List.map (fun (k, v) -> (match k with Some s -> s | None -> "name"), v) named_args) with
      | Some (VString s) -> s
      | _ -> (match List.hd named_args with (_, VString s) -> s | _ -> failwith "Expected string name")
    in
    let which_log = match List.assoc_opt "which_log" (List.map (fun (k, v) -> (match k with Some s -> s | None -> "which_log"), v) named_args) with
      | Some (VString s) -> Some s
      | _ -> None
    in
    Builder.read_node ?which_log name
  in
  Env.add "read_node" (make_builtin_named ~name:"read_node" 1 read_fn) env

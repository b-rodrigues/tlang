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
    let get_arg name pos default named_args =
      match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
      | Some v -> v
      | None ->
          let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
          if List.length positionals >= pos then List.nth positionals (pos - 1)
          else default
    in
    let name = match get_arg "name" 1 (VString "") named_args with
      | VString s -> s
      | _ -> failwith "Expected string name"
    in
    let which_log = match get_arg "which_log" 2 VNull named_args with
      | VString s -> Some s
      | _ -> None
    in
    Builder.read_node ?which_log name
  in
  Env.add "read_node" (make_builtin_named ~name:"read_node" ~variadic:true 1 read_fn) env

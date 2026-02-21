open Ast

(*
--# Load Pipeline Node Artifact
--#
--# Loads a node artifact by name from the latest (or specified) build log.
--# Equivalent to `read_node`; both support `which_log` for historical access.
--#
--# @name load_node
--# @param name :: String The node name.
--# @param which_log :: String (Optional) A regex pattern to match a specific build log filename.
--# @return :: Any The deserialized value.
--# @family pipeline
--# @seealso build_pipeline, read_node, inspect_pipeline
--# @export
*)
let register env =
  let load_fn named_args _env =
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
  Env.add "load_node" (make_builtin_named ~name:"load_node" 1 load_fn) env

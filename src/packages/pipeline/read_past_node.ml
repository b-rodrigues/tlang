open Ast
open Pipeline_utils

(*
--# Read Pipeline Node from a Past Build Run
--#
--# Reads and returns the contents of a pipeline node from a historical build
--# log, identified by `which_log`. Unlike `read_node`, this works without the
--# pipeline being in scope — the node name is captured via NSE from the
--# `p.node_name` syntax.
--#
--# @name read_past_node
--# @param node :: ComputedNode The node to read, written as `p.node_name` (NSE-captured).
--# @param which_log :: String A regex pattern matching a specific build log filename.
--# @return :: Any The deserialized artifact value, wrapped with diagnostics.
--# @family pipeline
--# @seealso read_node, list_logs, build_log
--# @export
*)
let read_past_node_fn named_args _env =
  let extract_arg name pos default args =
    match List.assoc_opt (Some name) args with
    | Some v -> v
    | None ->
        let positionals = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
        (match nth_safe (pos - 1) positionals with
         | Some v -> v
         | None -> default)
  in
  let node_expr = extract_arg "node" 1 (VNA NAGeneric) named_args in
  match extract_arg "which_log" 2 (VNA NAGeneric) named_args with
  | VString s ->
      (match node_expr with
       | VExpr { node = DotAccess { field = name; _ }; _ } ->
           (match Builder.latest_logged_computed_node ~log_name_pattern:s name with
            | Some cn ->
                let raw_val = Builder.logged_node_value cn.cn_name cn in
                Builder.wrap_with_diagnostics cn.cn_name cn raw_val
            | None ->
                Error.make_error KeyError
                  (Printf.sprintf "read_past_node: node '%s' not found in any build log matching '%s'. Use list_logs() to inspect available logs."
                     name s))
        | other ->
            Error.type_error
              (Printf.sprintf "read_past_node: expected `p.node_name` syntax for the node argument, but got %s."
                 (Utils.type_name other)))
  | VNA _ ->
      Error.make_error ValueError "read_past_node: `which_log` is required."
  | other ->
      Error.type_error
        (Printf.sprintf "read_past_node: `which_log` expects a String, but got %s."
           (Utils.type_name other))

let register env =
  Env.add "read_past_node"
    (make_builtin_named ~name:"read_past_node" ~variadic:true 2 read_past_node_fn)
    env

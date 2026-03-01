(* src/packages/pipeline/node_docs.ml *)

(*
--# Configure a Pipeline Node
--#
--# Configure execution settings such as the runtime and custom serialized methods for a pipeline node. 
--# This function is typically used directly within a `pipeline { ... }` block to wrap expressions and 
--# enable cross-runtime evaluation.
--#
--# @name node
--# @param command :: Any (Optional) The expression to evaluate inside the node.
--# @param script :: Any (Optional) A path to a runtime script file to execute instead of `command`. For Python, the script should define `main()` (or set `result`) for the returned object to be serialized. For R, the last expression value is serialized. Cannot be used together with `command`.
--# @param serializer :: Symbol (Optional) Custom serializer function. Default = default.
--# @param deserializer :: Symbol (Optional) Custom deserializer function. Default = default.
--# @param functions :: String | List[String] (Optional) Files to source before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @param runtime :: Symbol (Optional) The runtime environment (T, R, Python). Default = T.
--# @return :: Any The evaluated return value of `script` or `command` (exactly one must be provided).
--# @family pipeline
--# @export
*)
let () = ()

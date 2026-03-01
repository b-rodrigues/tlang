(* src/packages/pipeline/pyn_docs.ml *)

(*
--# Configure a Python Pipeline Node
--#
--# A convenience wrapper around `node()` with `runtime = "Python"`. 
--# Used directly within a `pipeline { ... }` block to execute Python code.
--#
--# @name pyn
--# @param command :: Any (Optional) The expression to evaluate inside the Python node (must be enclosed in `<{ ... }>` blocks).
--# @param script :: Any (Optional) A path to a Python script file. If provided, it is executed instead of `command`. The script should define a callable `main()` (preferred) or set `result`; if neither is found, an error is raised. Cannot be used together with `command`.
--# @param serializer :: Symbol (Optional) Custom serializer function. Default = default.
--# @param deserializer :: Symbol (Optional) Custom deserializer function. Default = default.
--# @param functions :: String | List[String] (Optional) Python files to source before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @return :: Any The evaluated return value of `script` or `command`. Exactly one of `script` or `command` must be provided; omitting both is an error unless `noop = true`.
--# @family pipeline
--# @seealso node, rn
--# @export
*)
let () = ()

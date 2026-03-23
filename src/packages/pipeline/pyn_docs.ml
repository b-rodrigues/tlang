(* src/packages/pipeline/pyn_docs.ml *)

(*
--# Configure a Python Pipeline Node
--#
--# A convenience wrapper around `node()` with `runtime = "Python"`. 
--# Used directly within a `pipeline { ... }` block to execute Python code.
--#
--# @name pyn
--# @param command :: Any (Optional) The expression to evaluate inside the Python node (must be enclosed in `<{ ... }>` blocks). Mutually exclusive with `script`.
--# @param script :: String (Optional) Path to an external `.py` file to execute as the node body. Mutually exclusive with `command`. Sets the runtime to `Python` automatically.
--# @param serializer :: String | Function (Optional) Custom serializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".
--# @param deserializer :: String | Function (Optional) Custom deserializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".
--# @param functions :: String | List[String] (Optional) Python files to source before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @return :: Any The evaluated return value of the command.
--# @family pipeline
--# @seealso node, rn
--# @export
*)
let () = ()

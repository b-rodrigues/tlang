(* src/packages/pipeline/shn_docs.ml *)

(*
--# Configure a Shell Pipeline Node
--#
--# A convenience wrapper around `node()` with `runtime = "sh"`.
--# Use `shn()` inside a `pipeline { ... }` block to run POSIX shell commands
--# or `.sh` scripts, and optionally set `shell = "bash"` when Bash parsing is required.
--#
--# @name shn
--# @param command :: Any (Optional) The shell command or raw shell script body to execute. Mutually exclusive with `script`.
--# @param script :: String (Optional) Path to an external `.sh` file to execute as the node body. Mutually exclusive with `command`.
--# @param serializer :: String | Symbol | Function (Optional) Custom serializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string, a symbol (e.g. $arrow), or a built-in function name. Custom functions can also be used. Default = "default".
--# @param deserializer :: String | Symbol | Function (Optional) Custom deserializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string, a symbol (e.g. $arrow), or a built-in function name. Custom functions can also be used. Default = "default".
--# @param args :: Dict | List (Optional) Runtime arguments. Lists become positional CLI arguments for exec-style nodes.
--# @param shell :: String (Optional) Shell interpreter to invoke for shell-string mode or script-backed nodes. Default = "sh".
--# @param shell_args :: List[String] (Optional) Additional arguments passed to the shell interpreter.
--# @param functions :: String | List[String] (Optional) Additional files to include in the sandbox before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @return :: Any The evaluated return value of the command.
--# @family pipeline
--# @seealso node, rn, pyn
--# @export
*)
let () = ()

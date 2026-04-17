(* src/packages/pipeline/qn_docs.ml *)

(*
--# Configure a Quarto Pipeline Node
--#
--# A convenience wrapper around `node()` with `runtime = "Quarto"`.
--# Used directly within a `pipeline { ... }` block to render Quarto documents.
--#
--# @name qn
--# @param script :: String (Optional) Path to an external `.qmd` file to render. Mutually exclusive with `command`.
--# @param serializer :: String | Function (Optional) Custom serializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".
--# @param deserializer :: String | Function (Optional) Custom deserializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".
--# @param env_vars :: Dict (Optional) Environment variables to pass into the sandbox.
--# @param args :: Dict (Optional) Runtime/tool arguments. Use this to pass Quarto CLI arguments such as `subcommand`, `path`, `to`, and additional options. `output_dir` is reserved and managed automatically so the rendered result is stored as the node artifact.
--# @param functions :: String | List[String] (Optional) Files to source before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @return :: Any The evaluated return value of the command.
--# @family pipeline
--# @seealso node, rn, pyn, shn
--# @export
*)
let () = ()

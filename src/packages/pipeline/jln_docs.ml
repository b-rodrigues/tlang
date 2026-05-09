(* src/packages/pipeline/jln_docs.ml *)

(*
--# Configure a Julia Pipeline Node
--#
--# A convenience wrapper around `node()` with `runtime = "Julia"`. 
--# Used directly within a `pipeline { ... }` block to execute Julia code.
--#
--# @name jln
--# @param command :: Any (Optional) The expression to evaluate inside the Julia node (must be enclosed in `<{ ... }>` blocks). Mutually exclusive with `script`.
--# @param script :: String (Optional) Path to an external `.jl` file to execute as the node body. Mutually exclusive with `command`. Sets the runtime to `Julia` automatically.
--# @param serializer :: String | Symbol (Optional) Custom serializer strategy. Built-in values include ^csv and ^json. Default = ^csv.
--# @param deserializer :: String | Symbol (Optional) Custom deserializer strategy. Built-in values include ^csv and ^json. Default = ^csv.
--# @param functions :: String | List[String] (Optional) Julia files to source before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @return :: Any The evaluated return value of the command.
--# @family pipeline
--# @seealso node, rn, pyn
--# @export
*)
let () = ()

(* src/packages/pipeline/rn_docs.ml *)

(*
--# Configure an R Pipeline Node
--#
--# A convenience wrapper around `node()` with `runtime = "R"`. 
--# Used directly within a `pipeline { ... }` block to execute R code.
--#
--# @name rn
--# @param command :: Any (Optional) The expression to evaluate inside the R node (must be enclosed in `<{ ... }>` blocks).
--# @param script :: Any (Optional) A path to an R script file. If provided, it is executed instead of `command`, and the last expression value is serialized. Cannot be used together with `command`.
--# @param serializer :: Symbol (Optional) Custom serializer function. Default = default.
--# @param deserializer :: Symbol (Optional) Custom deserializer function. Default = default.
--# @param functions :: String | List[String] (Optional) R scripts to source before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @return :: Any The evaluated return value of `script` or `command` (exactly one must be provided).
--# @family pipeline
--# @seealso node, pyn
--# @export
*)
let () = ()

(* src/packages/pipeline/node_docs.ml *)

(*
--# Configure a Pipeline Node
--#
--# Configure execution settings such as the runtime and custom serialized methods for a pipeline node.
--# This function is typically used directly within a `pipeline { ... }` block to wrap expressions,
--# enable cross-runtime evaluation, and optionally render a `.qmd` document via `runtime = Quarto`.
--#
--# @name node
--# @param command :: Any (Optional) The expression to evaluate inside the node. Mutually exclusive with `script`.
--# @param script :: String (Optional) Path to an external `.R`, `.py`, or `.qmd` file to execute as the node body. Mutually exclusive with `command`. The runtime is auto-detected from the file extension when not explicitly provided.
--# @param runtime :: Symbol (Optional) The runtime environment (T, R, Python, Quarto). Default = T.
--# @param serializer :: Symbol (Optional) Custom serializer function. Default = default.
--# @param deserializer :: Symbol (Optional) Custom deserializer function. Default = default.
--# @param args :: Dict (Optional) Runtime/tool arguments. For Quarto, use this to pass CLI arguments such as `subcommand`, `path`, and additional options. `output_dir` is reserved and managed automatically so the rendered result is stored as the node artifact.
--# @param functions :: String | List[String] (Optional) Files to source before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @return :: Any The evaluated return value of the command.
--# @family pipeline
--# @export
*)
let () = ()

(* src/packages/pipeline/node_docs.ml *)

(*
--# Configure a Pipeline Node
--#
--# Configure execution settings such as the runtime and custom serialized methods for a pipeline node.
--# This function is typically used directly within a `pipeline { ... }` block to wrap expressions,
--# enable cross-runtime evaluation, render a `.qmd` document via `runtime = Quarto`, or
--# execute shell/CLI tools via `runtime = sh`.
--#
--# @name node
--# @param command :: Any (Optional) The expression to evaluate inside the node. Mutually exclusive with `script`.
--#   For `runtime = sh`, this is a String: either an executable name (exec mode) or a full command string (shell mode).
--# @param script :: String (Optional) Path to an external `.R`, `.py`, `.qmd`, or `.sh` file to execute as the node body.
--#   Mutually exclusive with `command`. The runtime is auto-detected from the file extension when not explicitly provided.
--# @param runtime :: Symbol (Optional) The runtime environment (T, R, Python, Quarto, sh). Default = T.
--#   Use `sh` for shell/CLI-backed nodes that execute arbitrary commands or scripts.
--# @param serializer :: Symbol (Optional) Custom serializer function. Default = default.
--#   For shell nodes, supported values include: `text`, `lines`, `json`, `arrow`.
--# @param deserializer :: Symbol (Optional) Custom deserializer function. Default = default.
--#   Accepts the same values as `serializer`.
--# @param args :: Dict | List (Optional) Runtime/tool arguments.
--#   For Quarto, use this to pass CLI arguments such as `subcommand`, `path`, and additional options.
--#   For `sh` exec mode, use a List of String arguments (the argv).
--#   `output_dir` is reserved and managed automatically so the rendered result is stored as the node artifact.
--# @param shell :: String (Optional) Shell interpreter for shell mode. Only used with `runtime = sh`.
--#   When set, the command is passed through this shell (e.g., `"sh"`, `"bash"`).
--#   Without this, the command is run directly (exec mode).
--# @param shell_args :: List[String] (Optional) Arguments for the shell interpreter.
--#   Only used with `runtime = sh` and `shell`. Defaults to `["-c"]` when omitted.
--#   Example: `list("-lc")` for login-shell evaluation.
--# @param env_vars :: Dict (Optional) Additional environment variables passed to the node.
--#   For shell nodes, upstream dependencies are also exposed as `T_NODE_<name>` variables.
--# @param functions :: String | List[String] (Optional) Files to source before execution.
--# @param includes :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @return :: Any The evaluated return value of the command.
--# @family pipeline
--# @export
*)
let () = ()

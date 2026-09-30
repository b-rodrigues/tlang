(* src/packages/pipeline/node_docs.ml *)

(*
--# Configure a Pipeline Node
--#
--# Configure execution settings such as the runtime and custom serialized methods for a pipeline node.
--# This function is typically used directly within a `pipeline { ... }` block to wrap expressions,
--# enable cross-runtime evaluation, and optionally render a `.qmd` document via `runtime = Quarto`.
--#
--# Node commands run in a fresh sandbox, not a closure. Outer data values
--# are inlined as frozen literals; block-local bindings stay local;
--# functions and builtins stay symbolic (share code via `functions`, not
--# bare references); quoted `to_expr`/`quo` code runs later at node
--# runtime. Reassigning a captured outer data variable is a construction
--# error.
--#
--# @name node
--# @param command :: Any (Optional) The expression to evaluate inside the node. Mutually exclusive with `script`.
--# @param script :: String (Optional) Path to an external `.R`, `.py`, or `.qmd` file to execute as the node body. Mutually exclusive with `command`. The runtime is auto-detected from the file extension when not explicitly provided.
--# @param runtime :: Symbol (Optional) The runtime environment (T, R, Python, Quarto). Default = T.
--# @param serializer :: Symbol | Dict (Optional) Serializer strategy: a built-in (`default`, `^csv`, `^json`, `^ipc`, `^parquet`, `^pmml`, `^onnx`, `^bin`, `^text`, `^tlang`), an inline custom dict, or a quoted custom function `custom("name")` declared in `functions`. Bare function names are rejected. Default is `default`.
--# @param deserializer :: Symbol | Dict (Optional) Deserializer strategy: same closed set as `serializer`. Default is `default`.
--# @param args :: Dict (Optional) Runtime/tool arguments. For Quarto, use this to pass CLI arguments such as `subcommand`, `path`, and additional options. `output_dir` is reserved and managed automatically so the rendered result is stored as the node artifact.
--# @param functions :: String | List[String] (Optional) Files to source before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @param flake :: String (Optional) A Nix flake reference (e.g. "github:b-rodrigues/tlang") to use for this node's build environment. Default = NA (use project flake).
--# @return :: NodeDef A pipeline node configuration object. Must be used as a named binding inside a `pipeline { ... }` block; the node code is executed by the pipeline builder, not immediately.
--# @family pipeline
--# @export
*)
let () = ()

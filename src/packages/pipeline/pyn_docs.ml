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
--# @param serializer :: Strategy (Optional) Serializer strategy: a built-in (`default`, `^csv`, `^json`, `^ipc`, `^parquet`, `^pmml`, `^onnx`, `^bin`, `^text`, `^tlang`) or a strategy dict `[format: ^name, ...snippets]` (see `docs/serializers.md`). Bare function names are rejected. Default is `default`.
--# @param deserializer :: Strategy (Optional) Deserializer strategy: same closed set as `serializer`. Default is `default`.
--# @param functions :: String | List[String] (Optional) Python files to source before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @param flake :: String (Optional) A Nix flake reference (e.g. "github:b-rodrigues/tlang") to use for this node's build environment. Default = NA (use project flake).
--# @return :: NodeDef A pipeline node configuration object. Must be used as a named binding inside a `pipeline { ... }` block; the Python code is executed by the pipeline builder, not immediately.
--# @note When a Python node returns a `matplotlib` or `plotnine` plot object, T stores structured plot metadata so the REPL can display the plot class (`matplotlib` or `plotnine`), runtime backend, title, mappings, labels, and layers instead of the raw Python object.
--# @family pipeline
--# @seealso node, rn
--# @export
*)
let () = ()

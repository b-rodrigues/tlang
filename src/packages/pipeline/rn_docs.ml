(* src/packages/pipeline/rn_docs.ml *)

(*
--# Configure an R Pipeline Node
--#
--# A convenience wrapper around `node()` with `runtime = "R"`. 
--# Used directly within a `pipeline { ... }` block to execute R code.
--#
--# @name rn
--# @param command :: Any (Optional) The expression to evaluate inside the R node (must be enclosed in `<{ ... }>` blocks). Mutually exclusive with `script`.
--# @param script :: String (Optional) Path to an external `.R` file to execute as the node body. Mutually exclusive with `command`. Sets the runtime to `R` automatically.
--# @param serializer :: Symbol | Dict (Optional) Serializer strategy: a built-in (`default`, `^csv`, `^json`, `^ipc`, `^parquet`, `^pmml`, `^onnx`, `^bin`, `^text`, `^tlang`), an inline custom dict, or a quoted custom function `custom("name")` declared in `functions`. Bare function names are rejected. Default is `default`.
--# @param deserializer :: Symbol | Dict (Optional) Deserializer strategy: same closed set as `serializer`. Default is `default`.
--# @param functions :: String | List[String] (Optional) R scripts to source before execution.
--# @param include :: String | List[String] (Optional) Additional files for the sandbox.
--# @param noop :: Bool (Optional) Whether to skip execution and generate a stub. Default = false.
--# @param flake :: String (Optional) A Nix flake reference (e.g. "github:b-rodrigues/tlang") to use for this node's build environment. Default = NA (use project flake).
--# @return :: NodeDef A pipeline node configuration object. Must be used as a named binding inside a `pipeline { ... }` block; the R code is executed by the pipeline builder, not immediately.
--# @note When an R node returns a `ggplot2` object, T stores structured plot metadata so the REPL can display the plot class, title, mappings, labels, and layers without dumping the raw R object.
--# @family pipeline
--# @seealso node, pyn
--# @export
*)
let () = ()

# Serializers in T

T uses a first-class serializer system to manage data interchange between different runtimes (T, R, Python, Julia) and for materializing pipeline nodes as persistent artifacts.

## 1. Using Serializers

Serializers are identified by the `^` prefix. You can specify them when defining pipeline nodes:

```t
p = pipeline {
  -- Use the built-in Arrow IPC serializer for a DataFrame
  data = node(command = read_csv("large.csv"), serializer = ^ipc)
  
  -- Use the PMML serializer for a model
  model = rn(command = <{ lm(y ~ x, data = data) }>, serializer = ^pmml)
  
  -- Use the JSON serializer for a simple dictionary
  config = node(command = { "debug": true, "retries": 5 }, serializer = ^json)
}
```

### Symbols vs. Variables

T distinguishes between **built-in symbols** and **custom serializer variables**:

- **Symbols (`^ipc`, `^json`, etc.)**: Use the `^` prefix for T's built-in serializers. These are registered symbols that the pipeline emitter understands natively across all supported runtimes.
- **Variables (`my_serializer`)**: If you have defined a custom serializer in a variable (e.g., a dictionary imported from another file), pass the variable name **without** the `^` prefix. This allows the evaluator to pass the actual serializer definition to the node.

```t
-- Built-in symbol (uses T's internal logic)
node(..., serializer = ^ipc)

-- Custom variable (passes the dictionary value)
import "src/my_ser.t" [my_ser]
node(..., serializer = my_ser)
```

> [!IMPORTANT]
> **String literals (e.g., `serializer = "ipc"`) are strictly disallowed in node constructors** (`rn()`, `pyn()`, `jln()`, `shn()`, `qn()`, `node()`). You must use either a symbol with the `^` prefix for built-ins or a variable name for custom serializers. Using a string literal in a node constructor will result in a `TypeError`.
>
> `mutate_node()` and `set_pipeline_global_options()` accept both strings and symbols: `mutate_node($serializer = "pmml")` and `set_pipeline_global_options(p, serializer = ^pmml)` are both valid.


### Implicit Serialization
If you don't specify a serializer, T uses the `default` serializer, which selects each runtime's native binary format for in-language interchange (`serialize` for T, `saveRDS` for R, `pickle` for Python, and Julia's `Serialization` package). For shell nodes, `shn()` defaults to `^text`.

## 2. Built-in Serializers

| Identifier | Name | Best For | Write support | Read support | Notes |
|---|---|---|---|---|---|
| `^tlang` | T-Native | T-to-T interchange | T | T | Internal binary format |
| `^ipc` | Apache Arrow IPC | Large DataFrames | T, R, Python, Julia | T, R, Python, Julia | Fully symmetric across all runtimes |
| `^parquet` | Apache Parquet | Large DataFrames, columnar storage | T, R, Python, Julia | T, R, Python, Julia | Fully symmetric across all runtimes |
| `^csv` | CSV | Tabular data | T, R, Python, Julia | T, R, Python, Julia | Fully symmetric; R uses base `write.csv`/`read.csv` |
| `^json` | JSON | Config, lists, dicts | T, R, Python, Julia | T, R, Python, Julia | Fully symmetric; Python uses stdlib |
| `^pmml` | PMML | Predictive Models | T, R, Python, Julia | T, R, Python, Julia | Julia writer: GLM.jl → PMML 4.4; Julia reader: JPMML evaluator via `JavaCall` |
| `^onnx` | ONNX | ML Models | T, R, Python | T, R, Python, Julia | Julia: inference only (`ONNXRunTime.jl`); export is experimental/limited |
| `^text` | Plain Text | Logs, shell output | All | All | Raw text, no format constraints |
| `^bin` | Binary | Passthrough, fetchurl | T | T | Opaque binary blob; default for `fetchurl()` nodes |

## 3. The `serializer` Structure

A serializer is a first-class object in T. You can inspect its properties or even define your own.

```t
type serializer = {
  format: string,
  writer: function(path: string, value: any) -> result[NA, string],
  reader: function(path: string) -> result[any, string]
}
```

### Custom Serializers

You can create a custom serializer by defining a record that matches the required interface. Note that the `format` field should use a **Symbol** (starting with `^`) to remain consistent with T's symbol-based serialization mandate.

```t
my_log_serializer = {
  format: ^log,
  writer: \(path, val) {
    -- custom logic to write log
    Ok(NA)
  },
  reader: \(path) {
    -- custom logic to read log
    Ok("log content")
  }
}

-- Usage: Pass the variable name (no ^ hat on the variable itself!)
node(command = ..., serializer = my_log_serializer)
```

For a complete example of a cross-language custom serializer (YAML), see the [Custom Polyglot Serializer Demo](https://github.com/b-rodrigues/t_demos/blob/master/custom_polyglot_serializer_t/src/pipeline.t) in the `t_demos` repository.

## 4. Static Coherence Checks

One of the most powerful features of T's serializer system is the **static coherence check**. When you build a pipeline, T verifies that the format produced by a source node matches the format expected by the consumer node.

```t
node A {
  target: wn("data.csv", serializer = ^csv)
}

node B {
  source: rn("data.csv", serializer = ^ipc)
}

-- Result: Static Error
-- "Format mismatch: Node A produces ^csv, but Node B expects ^ipc."
```

This prevents runtime errors after long-running computations by catching interchange mismatches at the start of the build.

## 5. Serializer Runtime Dependencies

When you build a pipeline, T scans every node's serializer and runtime to determine which packages are needed, then checks `tproject.toml` for those packages. If any are missing, T **prompts you** with the exact `[r-dependencies]`, `[py-dependencies]`, and `[jl-dependencies]` entries to add before proceeding. You must then run `t update` and re-enter `nix develop` for the packages to become available. (Set `TLANG_AUTO_ADD_PIPELINE_DEPS=1` to skip the prompt in CI — T auto-appends the missing entries and exits with instructions to rerun the build.)

The table below shows which packages each format pulls in per runtime:

| Format | R packages | Python packages | Julia packages |
|--------|-----------|----------------|---------------|
| `^csv` | *(base R)* | `pandas` | `CSV`, `DataFrames` |
| `^ipc` | `arrow` | `pandas`, `pyarrow` | `Arrow`, `DataFrames` |
| `^parquet` | `arrow` | `pandas`, `pyarrow` | `Arrow`, `DataFrames` |
| `^json` | `jsonlite` | *(stdlib)* | `JSON` |
| `^pmml` | `XML`, `jsonlite`, `r2pmml` | `numpy`, `pandas`, `pyarrow`, `scikit-learn`, `scipy`, `sklearn2pmml`, `statsmodels` | `GLM`, `JavaCall` |
| `^onnx` | `onnx` | `onnxruntime`, `skl2onnx` | `ONNXRunTime`, `ONNX` |
| `^text` | *(base R)* | *(stdlib)* | *(stdlib)* |
| `^bin` | *(none)* | *(none)* | *(none)* |
| `default` | *(none)* | *(stdlib pickle)* | *(stdlib Serialization)* |

The `^pmml` format also requires the `jre` system tool for R, Python, and Julia nodes (for JPMML evaluator execution). Add `"jre"` to `[additional-tools].packages` in `tproject.toml`.

## 6. Polyglot Support

For cross-language nodes, serializers provide the necessary glue code for the target runtime. For example, when using `^ipc` in an R node:

1. T injects the `arrow` R library into the build environment.
2. T generates the R code to call `arrow::write_ipc_file()`.
3. T ensures the resulting file is correctly tracked as a Nix artifact.

### Custom Polyglot Serializers: R and Python Snippets

For a serializer to work across non-T runtimes, it can optionally provide code snippets for R and Python. These snippets are strings that T injects into the generated build scripts.

You can define these by adding `r_writer`, `r_reader`, `py_writer`, or `py_reader` keys to your serializer dictionary. You can use standard strings or **foreign code blocks** `<{ ... }>` for better readability:

```t
my_custom_ser = [
  format: ^custom,
  
  -- T implementation
  writer: \(path, val) { Ok(NA) },
  reader: \(path) { Ok(42) },
  
  -- R snippets (using foreign code blocks)
  r_writer: <{ function(obj, path) { saveRDS(obj, path) } }>,
  r_reader: <{ function(path) { readRDS(path) } }>,
  
  -- Python snippets
  py_writer: <{ lambda obj, path: pickle.dump(obj, open(path, 'wb')) }>,
  py_reader: <{ lambda path: pickle.load(open(path, 'rb')) }>
]
```

#### Injected Code Patterns

When T processes a node with an `R` runtime and the above serializer:
1. It looks for the `r_writer` snippet.
2. It generates a call in the node's R script: `<r_writer>(node_result, "artifact_path")`.

#### Registering Custom Formats

If you use a custom format name (e.g., `format: "myformat"`), you should ensure that your R or Python scripts have the necessary libraries loaded to handle that format. You can do this by adding the libraries to your `tproject.toml` or using the `functions` / `includes` parameters in the node definition.

For ONNX specifically, Julia nodes read model artifacts through `ONNXRunTime.jl` via the built-in `jl_read_onnx()` helper. Julia ONNX export is not supported yet, so `jl_write_onnx()` fails explicitly instead of silently falling back to another format.

---

## Next Steps

1. **[Pipeline Tutorial](pipeline_tutorial.md)** — Learn how pipelines use serializers for polyglot data interchange.
2. **[Data I/O & Formats](data-formats.md)** — Read and write CSV, Parquet, and Arrow IPC files; download data from URLs.
3. **[Project Development](project_development.md)** — Declare runtime dependencies so serializer packages are available at build time.

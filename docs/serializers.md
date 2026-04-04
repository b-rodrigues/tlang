# Serializers in T

T uses a first-class serializer system to manage data interchange between different runtimes (T, R, Python, Julia) and for materializing pipeline nodes as persistent artifacts.

## 1. Using Serializers

Serializers are identified by the `^` prefix. You can specify them when defining pipeline nodes:

```t
p = pipeline {
  -- Use the built-in Arrow serializer for a DataFrame
  data = node(command = read_csv("large.csv"), serializer = ^arrow)
  
  -- Use the PMML serializer for a model
  model = rn(command = <{ lm(y ~ x, data = data) }>, serializer = ^pmml)
  
  -- Use the JSON serializer for a simple dictionary
  config = node(command = { "debug": true, "retries": 5 }, serializer = ^json)
}
```

### Implicit Serialization
If you don't specify a serializer, T uses the `^tlang` (internal binary) format for T-to-T communication. For other runtimes, T attempts to infer a sensible default based on the data type or the specific wrapper used (e.g., `shn()` defaults to `^text`).

## 2. Built-in Serializers

| Identifier | Name | Best For | Compatibility |
|---|---|---|---|
| `^tlang` | T-Native | T-to-T interchange | T only |
| `^arrow` | Apache Arrow | Large DataFrames | T, R, Python, Julia |
| `^pmml` | PMML | Predictive Models | T, R, Python |
| `^onnx` | ONNX | ML Models | T, R, Python |
| `^json` | JSON | Config, lists, dicts | T, R, Python |
| `^csv` | CSV | Tabular data | T, R, Python |
| `^text` | Plain Text | Logs, shell output | All |

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

You can create a custom serializer by defining a record that matches the required interface:

```t
my_log_serializer = {
  format: "log",
  writer: \(path, val) {
    -- custom logic to write log
    Ok(NA)
  },
  reader: \(path) {
    -- custom logic to read log
    Ok("log content")
  }
}

-- Usage
node(command = ..., serializer = my_log_serializer)
```

## 4. Static Coherence Checks

One of the most powerful features of T's serializer system is the **static coherence check**. When you build a pipeline, T verifies that the format produced by a source node matches the format expected by the consumer node.

```t
node A {
  target: wn("data.csv", serializer = ^csv)
}

node B {
  source: rn("data.csv", serializer = ^arrow)
}

-- Result: Static Error
-- "Format mismatch: Node A produces ^csv, but Node B expects ^arrow."
```

This prevents runtime errors after long-running computations by catching interchange mismatches at the start of the build.

## 5. Polyglot Support

For cross-language nodes, serializers provide the necessary glue code for the target runtime. For example, when using `^arrow` in an R node:

1. T injects the `arrow` R library into the build environment.
2. T generates the R code to call `arrow::write_ipc_file()`.
3. T ensures the resulting file is correctly tracked as a Nix artifact.

### Custom Polyglot Serializers: R and Python Snippets

For a serializer to work across non-T runtimes, it can optionally provide code snippets for R and Python. These snippets are strings that T injects into the generated build scripts.

You can define these by adding `r_writer`, `r_reader`, `py_writer`, or `py_reader` keys to your serializer dictionary. You can use standard strings or **foreign code blocks** `<{ ... }>` for better readability:

```t
my_custom_ser = [
  format: "custom",
  
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

For more information on how pipelines use these serializers, see the [Pipeline Tutorial](pipeline_tutorial.md).

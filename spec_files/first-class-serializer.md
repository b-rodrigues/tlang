# Brainstorming: First-class Serializer System

This document outlines the design for a first-class serializer system in T. Currently, serialization is handled by internal functions (supporting OCaml Marshal for binary and Yojson for JSON). Moving to a first-class system allows for greater extensibility, custom formats, and static guarantees during pipeline orchestration.

## 1. The `serializer` Structure

A `serializer` is a built-in structure (or a specific record type) that provides the necessary interface for reading and writing data.

```t
type serializer = {
  writer: function(path: string, value: any) -> result[null, string],
  reader: function(path: string) -> result[any, string],
  format: string -- e.g., "csv", "arrow", "json"
}
```

### Internal representation in OCaml (`src/ast.ml`)
```ocaml
and serializer = {
  s_writer : value; (* VLambda or VBuiltin *)
  s_reader : value; (* VLambda or VBuiltin *)
  s_format : string;
}

and value = 
  ...
  | VSerializer of serializer
```

### Proposed Interface
The `writer` and `reader` functions are the core of the system.
- `writer(path, value)`: Takes a filesystem path and the value to be stored. Returns `Ok(null)` on success or `Error(msg)` on failure.
- `reader(path)`: Takes a filesystem path and returns `Ok(value)` or `Error(msg)`.

## 2. The `^` Identifier Prefix

To differentiate serializers from standard variables or keywords, we propose using the caret `^` prefix. This matches the ergonomic needs of pipeline definitions where format selection should be concise.

### Examples
- `^csv` resolves to the built-in CSV serializer.
- `^arrow` resolves to the Arrow IPC / Feather serializer.
- `^json` resolves to the JSON serializer.
- `^parquet` resolves to the Parquet serializer.
- `^tlang` (or `^bin`) resolves to the internal OCaml-compatible binary format.

### Lexer Change
We need to add a new token for serializer identifiers:
```ocaml
| '^' (identifier as name) { SERIALIZER_ID name }
```

## 3. Usage in Pipelines and Nodes

Serializers can be passed as arguments to orchestration functions like `read_node` and `write_node`.

```t
-- Explicitly using a serializer
data = read_node("data/raw.csv", serializer = ^csv)

-- In a pipeline definition
p = pipeline {
  source: rn("input.feather", serializer = ^arrow),
  transform: df |> filter($age > 20),
  target: wn("output.parquet", serializer = ^parquet)
}
```

### Default Serializer
If no serializer is provided, the system could:
1. Infer based on file extension (e.g., `.csv` -> `^csv`).
2. Fallback to `^tlang` for internal node interchange.

## 4. Static Coherence Checks

One of the primary benefits of first-class serializers is the ability to perform **static coherence checks** in the pipeline builder.

### The Problem
If `node_A` writes a CSV file, but `node_B` expects to read an Arrow file from the same path, the pipeline will fail at runtime after potentially expensive computations.

### The Solution: Type/Format Matching
The pipeline builder can track the "format" produced by a node.

```t
node A {
  target: wn("tmp/data.csv", serializer = ^csv)
}

node B {
  source: rn("tmp/data.csv", serializer = ^arrow)
}

-- Static Error:
-- Format mismatch for "tmp/data.csv". Node A produces ^csv, but Node B expects ^arrow.
```

### Implementation in the Pipeline Builder
1. Maintain a map of `path -> serializer_format` during the DAG construction.
2. If a path is used as a target multiple times, verify they use the same serializer.
3. If a path is used as a source, verify it matches the serializer used by the producing node.

## 5. ComputedNode Integration

The `ComputedNode` type in `src/ast.ml` currently stores `cn_serializer` as a `string`. 

```ocaml
and computed_node = {
  cn_name : string;
  cn_runtime : string;
  cn_path : string;
  cn_serializer : string; -- Needs to remain a string for Nix-store serialization, 
                          -- but should resolve to a VSerializer at runtime.
  cn_class : string;
  cn_dependencies : string list;
}
```

When `read_node` is called on a `ComputedNode`, the system will:
1. Lookup the `VSerializer` named `cn_serializer`.
2. Invoke its `.reader` function on `cn_path`.

## 5. Custom Serializers

Users should be able to define their own serializers by creating a record that matches the interface.

```t
my_custom_serializer = {
  writer: function(path, val) { 
    -- custom logic to write val to path
    Ok(null)
  },
  reader: function(path) {
    -- custom logic to read from path
    Ok(data)
  },
  format: "my-ext"
}

-- Usage
read_node("data.custom", serializer = my_custom_serializer)
```

## 6. Implementation Notes

- **Source Files to Modify**:
    - `src/lexer.mll`: Add `^` prefix support.
    - `src/parser.mly`: Add `SERIALIZER_ID` token and expression rule.
    - `src/ast.ml`: Add `VSerializer` variant to `value`.
    - `src/serialization.ml`: Implement the built-in serializers (`^csv`, `^arrow`, etc.) as `VSerializer` values.
    - `src/pipeline_builder.ml`: Implement the coherence check logic.
- **Built-in Registry**: A global registry of serializers could allow `^` to look up by name.

## 7. Polyglot Runtime Support

For a serializer to work across runtimes (R, Python, T), it needs to provide implementation snippets for each.

```t
type serializer = {
  format: string,
  
  -- T implementations (first-class functions)
  writer: function(path: string, value: any) -> result[null, string],
  reader: function(path: string) -> result[any, string],
  
  -- R implementation (code snippets)
  r_writer: string, -- e.g., "function(obj, path) { write.csv(obj, path) }"
  r_reader: string, -- e.g., "function(path) { read.csv(path) }"
  
  -- Python implementation (code snippets)
  py_writer: string,
  py_reader: string
}
```

The `Nix_emit_node.ml` emitter will be refactored to:
1. Identifying the `VSerializer` used by the node.
2. Inject the appropriate `r_writer` / `py_writer` snippet into the build script.
3. Call the injected function for serialization.

## 8. Static Coherence Refinement

The pipeline builder's `populate_pipeline` function will be updated to:
- Build a map of `ProducedFormat(path) -> serializer_id`.
- For every `read_node(path, serializer = S)`, check if `ProducedFormat(path)` is compatible with `S`.
- Built-in serializers like `^arrow` will have a unique `format_id` to ensure strict matching.

## 9. Testing Requirements

A comprehensive test suite must be implemented to verify both the ergonomic and the robust qualities of the first-class serializer system.

### Happy Path Tests
- **Built-in Registry Resolution**: Verify that `^csv` and `^arrow` correctly resolve to the built-in serializer records.
- **Pipeline Data Flow**: Test a multi-node pipeline where:
  - Node A produces ^arrow.
  - Node B consumes ^arrow.
  - Node C consumes ^arrow and produces ^json.
- **Custom Serializers**: Ensure a user-defined record with `writer/reader` functions can be used in `read_node/write_node`.
- **Lexer/Parser**: verify that `serializer = ^csv` is a valid argument in `node()`, `rn()`, and `pyn()`.

### Error Handling Tests
- **Format Mismatch**: A node specifies `serializer = ^csv` but its consumer specifies `deserializer = ^arrow`. Verify the static error message is clear and includes both node names and formats.
- **Missing implementation**: If a serializer is used in an R node but lacks `r_writer/r_reader`, verify a clear error is thrown during pipeline population.
- **Serialization Failure**: Test runtime behavior when a serializer's `writer` function returns an `Error` (e.g., Disk Full or Permission Denied).
- **Invalid Identifiers**: Ensure `^non_existent` results in a NameError or a specialized "Unknown Serializer" error.
- **Cycle Detection & Coherence**: Verify that adding a serializer doesn't interfere with the existing DAG cycle detection.

## 10. Next Steps

- [ ] Update `src/ast.ml` with `VSerializer` and record type.
- [ ] Add `^` identifier support to `lexer.mll` and `parser.mly`.
- [ ] Implement `src/serialization_registry.ml` to hold built-in serializers.
- [ ] Refactor `Nix_emit_node.ml` to use the snippets from `VSerializer`.
- [ ] Update `populate_pipeline.ml` with static coherence checks.

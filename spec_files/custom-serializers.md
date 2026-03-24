# Brainstorming: Custom Serializers and Deserializers in T

## Problem Statement

Currently, T allows users to specify serializers and deserializers for node I/O. For built-in formats like `csv`, `arrow`, or `pmml`, the system knows which functions to use. However, for custom formats, users must pass individual functions (e.g., `read_blob` and `write_blob`).

The main issues with the current approach are:
1. **Lack of Coherence Checks:** There's no built-in mechanism to ensure that if Node A writes data using `write_blob`, Node B expects to read it using `read_blob`.
2. **Repetitive Configuration:** Users must specify the functions for every node, even if they always go together.
3. **Identifier Inconsistency:** Built-in formats use string identifiers ("csv"), while custom ones use function references.

## Proposed Solution: The `serializer` Structure

We should introduce a unified `serializer` structure that pairs a `writer` function with its corresponding `reader`.

### 1. Unified Structure

A `serializer` would be defined as a structured object:

```t
blob = serializer(
    id = "blob",
    writer = write_blob,
    reader = read_blob,
    extension = ".bin"
)
```

### 2. Refactoring Built-ins

Built-in formats like `csv` and `arrow` should be pre-registered instances of this structure.

```t
# standard library setup
csv = serializer(
    id = "csv",
    writer = standard::write_csv,
    reader = standard::read_csv,
    extension = ".csv"
)

arrow = serializer(
    id = "arrow",
    writer = standard::write_arrow,
    reader = standard::read_arrow,
    extension = ".arrow"
)
```

### 3. Usage in Nodes

Nodes would now accept a `serializer` object. This simplifies the configuration and allows for validation.

```t
p = pipeline {
  data_gen = node(
      command = <{ ... }>,
      runtime = "Python",
      serializer = blob
  )

  data_process = node(
      command = <{ ... }>,
      runtime = "R",
      deserializer = [data_gen: blob],
      serializer = csv
  )
}
```

## Coherence Validation

With this grouping, T can perform static or runtime checks during pipeline construction:

1. **Identifier Matching:** When creating a link from `data_gen` to `data_process`, the compiler checks if the `serializer` of the source node matches the `deserializer` expected by the target node.
2. **Pipeline Safety:** If `data_gen` uses `serializer = blob` and `data_process` uses `deserializer = [data_gen: csv]`, the pipeline should fail to build with a clear error:
   > "Mismatch in data interchange format: Node 'data_gen' writes using 'blob', but Node 'data_process' expects 'csv'."

## Brainstorming: Registration and Scoping

This seems like the most straightforward approach:

```t
blob = serializer(read_blob, write_blob)

node_a = node(
    command = <{ ... }>,
    serializer = blob
)
```

## Transition Plan

1. **Deprecate separate function references:** Move towards a single `serializer` or `deserializer` field that accepts these objects.
2. **Internal Refactor:** Update the OCaml builder to treat all I/O as being governed by a `serializer` object. Even if the user passes a string `"csv"`, it's resolved to the built-in `csv` serializer object.
3. **Validation Logic:** Add a check in the pipeline builder that compares the identifiers of connected nodes.

## Identifier Strategies

### Explicit Human-Readable IDs
```t
blob = register_serializer(
    id = "blob",
    writer = write_blob,
    reader = read_blob
)
```

`blob` is now an object of class `serializer`.

- **Pros:** Easy to debug ("X says blob, Y says csv").
- **Cons:** Collision potential if two users define "blob" with different functions.

## Naming Conventions: `csv` vs `CSV`

To distinguish `serializer` objects from standard variables or functions, we should establish a clear naming convention. 

### Option 1: All Caps (e.g., `CSV`, `ARROW`, `PMML`)
Since T already uses all-caps identifiers for runtimes (e.g., `runtime = R`, `runtime = Python`), using all-caps for built-in serialization objects provides high visibility and consistency.

```t
node_a = node(
    command = <{ ... }>,
    serializer = CSV
)
```
- **Pros:** Clearly signals "this is a first-class system object". Consistent with existing runtime constants.
- **Cons:** Might look "shouty" or outdated to some developers.

### Option 2: Pascal Case (e.g., `Csv`, `Arrow`)
Matches the naming convention of T's core types (e.g., `DataFrame`, `Tensor`).
- **Pros:** Consistent with type names.
- **Cons:** Might be confused with a class constructor call if the language supports them.

### Option 4: Symbol-Prefixed (e.g., `^csv`, `^arrow`)
Inspired by how Clojure or Ruby use `:` for keywords/symbols, or T's own use of `$` for column references.

```t
node_a = node(
    command = <{ ... }>,
    serializer = ^csv
)
```
- **Pros:** Very clean. Immediate visual signal that `^csv` is a specific "Serializer Object" and not a variable or function. Can be lowercase without risk of conflict with local variables.
- **Cons:** Requires a small update to the lexer and parser to recognize the `^` prefix (similar to how `$` is handled).

### Recommendation
While **ALL_CAPS** (`CSV`) is the easiest to implement immediately using existing infrastructure, the **Symbol-Prefix** (`^csv`) is an elegant long-term solution that fits T's ergonomic design (mirroring `$col`).

```t
^blob = register_serializer(
    id = "blob",
    writer = write_blob,
    reader = read_blob
)

node_a = node(..., serializer = ^blob)
```

## Benefits

- **Safety:** Prevents hard-to-debug "corrupted data" errors caused by mismatched read/write functions.
- **Simplicity:** Familiar formats like `^blob` become first-class citizens of the same system used for custom blobs.
- **Extensibility:** Users can easily share serializer packages (e.g., a lib that provides Parquet serialization).
- **Consistency:** Provides a unified interface for both built-in and user-provided serialization.

## Phased Implementation Approach

### Phase 1: Core AST and Lexer Updates
- **Lexer**: Add a rule to recognize the \^\ prefix as a special identifier type (e.g., \SERIALIZER_ID\).
- **AST**: Define the \serializer\ object type in OCaml, containing \id\, \writer\, \eader\, and \extension\.
- **Environment**: Pre-populate the T environment with the standard \serializer\ constructor.

### Phase 2: Refactoring Built-ins
- **Standard Library**: Migrate \csv\, \rrow\, and \pmml\ to be children of the new \serializer\ type.
- **Node API**: Update the ode()\ and \n()\ functions to accept these objects in addition to (and eventually instead of) raw strings.
- **Backwards Compatibility**: Ensure passing \ÿ

# Proposal: `build_log_history` and `node_diff`

## Motivation

T currently provides excellent introspection into the *current* state of a pipeline via `build_log`, `pipeline_cache_status`, and `pipeline_to_store`. What is missing is a temporal dimension: the ability to reason about how a pipeline's outputs have *changed across builds*. This is particularly relevant for iterative analytical work — refactoring a model node, updating a data source, or changing a serializer — where the analyst needs to verify that the change produced the expected effect on the artifact.

`build_log_history` and `node_diff` form a pair that addresses this gap. The former exposes the historical record of builds; the latter makes the artifacts from those builds directly comparable.

---

## 1. `build_log_history(p, n = NA)`

### Description

Returns a summary DataFrame of all historical builds matching the current pipeline's node signature, ordered from most recent to oldest.

### Signature

```t
build_log_history(p)
build_log_history(p, n = 5)   -- last 5 builds only
```

### Returns

A DataFrame with one row per matching build and the following columns:

| Column | Type | Description |
|---|---|---|
| `build_id` | Int | 1-indexed rank, 1 = most recent |
| `timestamp` | String | ISO 8601 build timestamp |
| `duration` | Float | Total build duration in seconds |
| `n_nodes` | Int | Total number of nodes in the build |
| `n_failed` | Int | Number of failed/errored nodes |
| `n_warnings` | Int | Number of nodes with warnings |
| `out_path` | String | Nix store output path for the build |
| `hash` | String | Content hash of the build output |

### Design Notes

- Uses the existing `find_latest_matching_log_path` signature-matching logic to filter logs to only those that match the current pipeline definition. Logs from structurally different pipeline versions are excluded.
- `n = NA` returns all matching logs. `n = 1` is equivalent to `build_log` but in tabular form.
- The `out_path` column is the key that connects `build_log_history` to `node_diff` — it identifies the Nix store root from which individual node artifacts can be resolved.

### Example

```t
p = pipeline {
  data = read_csv("cohort.csv")
  model = rn(command = <{ lm(wage ~ age, data = data) }>, serializer = ^pmml)
  scored = node(command = data |> mutate($pred = predict(data, model)))
}

-- Inspect build history
history = build_log_history(p)
print(history)

-- Find builds with failures
history |> filter($n_failed > 0)

-- Check if recent builds are getting faster or slower
history |> select([$build_id, $timestamp, $duration]) |> head(10)
```

### Implementation

Thin wrapper over existing infrastructure:

1. Call `list_logs()` to enumerate `_pipeline/build_log_*.json` files
2. Filter using `find_latest_matching_log_path` signature matching
3. For each matching log, extract the summary fields (already present in the JSON structure)
4. Assemble into a DataFrame sorted by timestamp descending
5. Apply `n` truncation if provided

No new OCaml dependencies. Estimated ~60 lines in a new `build_log_history.ml`.

---

## 2. `node_diff(p, node, build_a = 1, build_b = 2)`

### Description

Compares the artifact produced by a named node across two historical builds. Dispatches to a type-appropriate comparison based on the node's serializer, returning a structured diff value.

### Signature

```t
node_diff(p, "model")              -- compare most recent vs. second most recent
node_diff(p, "model", 1, 3)        -- compare build 1 vs. build 3 (1-indexed from build_log_history)
node_diff(p, "model", build_a = 2, build_b = 4)
```

`build_a` and `build_b` are `build_id` values from `build_log_history` — 1 is the most recent build.

### Returns

The return type depends on the node's serializer:

**DataFrame nodes** (`^csv`, `^arrow`, `^parquet`):

A Dict with the following keys:

```t
[
  schema_changed: Bool,
  added_columns: List[String],
  removed_columns: List[String],
  nrows_a: Int,
  nrows_b: Int,
  nrows_added: Int,
  nrows_removed: Int,
  column_summaries: DataFrame  -- one row per shared column: name, type, mean_a, mean_b, mean_delta, n_changed
]
```

**Model nodes** (`^pmml`, `^onnx`):

A Dict with:

```t
[
  model_type: String,        -- e.g. "LinearRegression"
  coefficients_changed: Bool,
  coef_diff: DataFrame       -- one row per coefficient: name, value_a, value_b, delta
]
```

**Scalar nodes** (Int, Float, Bool, String):

```t
[
  value_a: <type>,
  value_b: <type>,
  changed: Bool,
  delta: Float  -- for numeric types; NA otherwise
]
```

**Text/JSON nodes**:

```t
[
  changed: Bool,
  lines_added: Int,
  lines_removed: Int,
  diff: String   -- unified diff format
]
```

### Error Cases

- Node name not found in pipeline → `NameError`
- `build_a` or `build_b` index out of range → `ValueError`
- Artifact no longer present in Nix store (garbage collected) → `FileError` with the store path in the error context, so the user knows which build to rebuild
- Serializer type changed between builds → `TypeError` with a clear message explaining the mismatch

### Example

```t
-- After refactoring the model node
node_diff(p, "model")
-- [
--   model_type: "LinearRegression",
--   coefficients_changed: true,
--   coef_diff: DataFrame(
--     name       value_a   value_b   delta
--     intercept  12.4      13.1      0.7
--     age        0.42      0.39     -0.03
--     educ       1.83      1.91      0.08
--   )
-- ]

-- After updating the data source
node_diff(p, "data")
-- [
--   schema_changed: false,
--   nrows_a: 4821,
--   nrows_b: 4903,
--   nrows_added: 82,
--   nrows_removed: 0,
--   column_summaries: DataFrame(...)
-- ]
```

### Implementation Notes

**Artifact resolution**: `node_diff` resolves artifact paths as:
```
<out_path from build_log_history row> / <node_name> / artifact
```
This is the same path structure already used by `build_pipeline` and `read_node`, so no new store conventions are needed.

**Serializer detection**: Read from the `serializer` field in the build log's per-node record — already stored in the JSON. This means `node_diff` works correctly even if the pipeline definition has changed the serializer since the historical build.

**DataFrame diffing**: The column-level summary for DataFrame nodes can be implemented using existing T stdlib operations (`anti_join`, `summarize`, column-wise arithmetic) rather than new OCaml code, keeping the implementation thin.

**PMML coefficient extraction**: Reuse the existing `Pmml_utils` module which already parses PMML into structured T values.

**ONNX diffing**: Limited to metadata comparison (input/output shapes, op counts) since ONNX binary weights are not directly human-readable. Full weight diffing is out of scope.

---

## Dependency Graph

```
build_log_history(p)
    └── list_logs()                     [exists]
    └── find_latest_matching_log_path() [exists]
    └── parse_json_log fields           [exists]

node_diff(p, node, a, b)
    └── build_log_history(p)            [new]
    └── read artifact from out_path     [exists via read_node path logic]
    └── serializer dispatch             [new, reuses existing serializer modules]
    └── Pmml_utils                      [exists]
    └── Arrow diff logic                [new, thin, uses existing stdlib ops]
```

---

## Sequencing

1. `build_log_history` first — it is self-contained, low risk, and is a hard dependency of `node_diff`.
2. `node_diff` scalar and text cases — simple, no new dependencies.
3. `node_diff` DataFrame case — requires the Arrow diff logic.
4. `node_diff` PMML case — reuses `Pmml_utils`, straightforward.
5. `node_diff` ONNX case — metadata only for now, full weight diff deferred.

Both functions are good candidates for 0.52.3 as a pair, keeping 0.52.2 focused on the Nix orchestration theme.
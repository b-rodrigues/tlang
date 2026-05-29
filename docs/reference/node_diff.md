# node_diff

Compare Node Outputs Across Builds

Compares the artifact produced by a node across two historical builds of the
same pipeline, or compares two different nodes. Returns a structured `VDiff`
dictionary with a consistent envelope.

Dispatches to a type-appropriate comparison:
- **DataFrame** → row-/column-level diff with optional key-based alignment
- **Model (PMML)** → coefficient deltas and fit-stat comparison
- **Scalar** → before/after with numeric delta
- **Python-native objects** → artifact deserialization through the bundled `tlang` Python package, then DeepDiff-based structural comparison
- **Julia-native objects** → artifact deserialization through the bundled `tlang` Julia package, then DeepDiffs-based structural comparison
- **R-native objects** → artifact deserialization through the bundled `tlang` R package, then diffobj-based structural comparison
- **Generic** → structural comparison over string representations

Runtime-native object diffs are preserved only for artifacts using the standard
`default` or `tobj` serializers. If you assign a custom serializer name (for
example `"rds"` or `"pkl"`), `node_diff()` falls back to the normal artifact
loading path; for those cases, call the companion R/Python/Julia helper
packages directly with an explicit deserializer.

For Julia-native artifacts, `node_diff()` launches a fresh Julia helper process
for each comparison. This keeps the integration simple but adds startup cost for
repeated or very large diffs.

## Signature

```t
node_diff(
  node_a    :: ComputedNode,
  node_b    :: ComputedNode,
  log_a     :: String = "latest",
  log_b     :: String = "latest",
  key       :: List[Symbol] = [],
  context   :: Int = 3
) :: VDiff
```

## Parameters

- **node_a** (`ComputedNode`): The "before" node, e.g. `p.clean_data`.
- **node_b** (`ComputedNode`): The "after" node, e.g. `p.clean_data`.
- **log_a** (`String`): Build log selector for `node_a`. Accepts `"latest"`, a timestamp prefix (`"20260510_120000"`), or a regex matched against filenames in `_pipeline/`. Default: `"latest"`.
- **log_b** (`String`): Build log selector for `node_b`. Same format as `log_a`. Default: `"latest"`.
- **key** (`List[Symbol]`): For DataFrames: the natural key column(s) used to align rows before diffing. If empty, rows are aligned by position. Default: `[]`.
- **context** (`Int`): Number of unchanged rows shown above and below each changed hunk. Default: `3`.


## Returns

`Dict`: A `VDiff` envelope dictionary with the following fields:

| Field | Type | Description |
|---|---|---|
| `kind` | `String` | `"dataframe_diff"`, `"model_diff"`, `"scalar_diff"`, `"python_object_diff"`, `"julia_object_diff"`, `"r_object_diff"`, or `"generic_diff"` |
| `node_a` | `String` | Name of the first node |
| `node_b` | `String` | Name of the second node |
| `log_a` | `String` | Resolved log filename for node_a |
| `log_b` | `String` | Resolved log filename for node_b |
| `value_type` | `String` | T type name of the diffed values |
| `identical` | `Bool` | `true` if no differences were found |
| `summary` | `Dict` | Type-specific summary counts |
| `detail` | `Dict` | Type-specific detail |
| `hunks` | `List[Dict]` | Diff hunks or rendered diff regions when available |

## Examples

```t
-- Compare the same node across two historical builds
d = node_diff(p.clean_data, p.clean_data,
      log_a = "20260510_120000",
      log_b = "20260515_090000")

-- Compare two different nodes in the current build
d = node_diff(p.clean_data, p.validated_data)

-- Same node, latest vs a named earlier run, keyed on an id column
d = node_diff(p.customers, p.customers,
      log_a = "20260501",
      log_b = "latest",
      key = [$customer_id])

-- Model comparison
d = node_diff(p.model_v1, p.model_v2)

-- Python-native artifact comparison (for example NumPy ndarrays)
d = node_diff(p.weights, p.weights, log_a = 1, log_b = 2)

-- Julia-native artifact comparison (for example serialized structs or arrays)
d = node_diff(p.julia_model, p.julia_model, log_a = 1, log_b = 2)

-- R-native artifact comparison (for example saved model objects)
d = node_diff(p.r_model, p.r_model, log_a = 1, log_b = 2)
```

## See Also

- `build_log` — retrieve build log for a pipeline
- `build_log_history` — list historical builds
- `explain` — structural explanation of any value, including VDiff

# node_diff

Compare Node Outputs Across Builds

Compares the artifact produced by a node across two historical builds of the
same pipeline, or compares two different nodes. Returns a structured `VDiff`
dictionary with a consistent envelope.

Dispatches to a type-appropriate comparison:
- **DataFrame** → row-/column-level diff with optional key-based alignment
- **Model (PMML)** → coefficient deltas and fit-stat comparison
- **Scalar** → before/after with numeric delta
- **Generic** → structural comparison over string representations

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
| `kind` | `String` | `"dataframe_diff"`, `"model_diff"`, `"scalar_diff"`, or `"generic_diff"` |
| `node_a` | `String` | Name of the first node |
| `node_b` | `String` | Name of the second node |
| `log_a` | `String` | Resolved log filename for node_a |
| `log_b` | `String` | Resolved log filename for node_b |
| `value_type` | `String` | T type name of the diffed values |
| `identical` | `Bool` | `true` if no differences were found |
| `summary` | `Dict` | Type-specific summary counts |
| `detail` | `Dict` | Type-specific detail |
| `hunks` | `List[Dict]` | Patience-diff hunks |

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
```

## See Also

- `build_log` — retrieve build log for a pipeline
- `build_log_history` — list historical builds
- `explain` — structural explanation of any value, including VDiff

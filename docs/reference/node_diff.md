# node_diff

Compare Node Outputs Across Builds

Compares the artifact produced by a named node across two historical builds of the same pipeline.  Returns a structured VDiff dictionary with a consistent envelope (kind, node_a, node_b, log_a, log_b, value_type, identical, summary, detail, hunks).  Dispatches to a type-appropriate comparison: - DataFrame → row-/column-level diff with optional key-based alignment - Model (PMML) → coefficient deltas and fit-stat comparison - Scalar → before/after with numeric delta - Python-native objects → unified_diff-based structural comparison - Julia-native objects → DeepDiffs-based structural comparison - R-native objects → diffobj-based structural comparison - Generic → structural comparison over string representations  Runtime-native object diffs are preserved only for runtime artifacts using the standard `default`/`tobj` serializers. Custom serializer names follow the normal artifact-loading path; use the companion helper packages directly when you need a custom deserializer for native objects.

## Parameters

- **node_a** (`ComputedNode`): The "before" node.

- **node_b** (`ComputedNode`): The "after" node.

- **log_a** (`String`): | Int Build log selector for node_a (default "latest"). Accepts a timestamp prefix, regex, or 1-indexed integer.

- **log_b** (`String`): | Int Build log selector for node_b (default "latest"). Same format as log_a.

- **key** (`List[Symbol]`): For DataFrames: natural key column(s) for row alignment (default []).

- **context** (`Int`): Number of unchanged rows shown around each hunk (default 3).


## Returns

A VDiff envelope dictionary.


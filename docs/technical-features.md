# Advanced Architecture & Technical Features

This guide details the advanced language features, metaprogramming facilities, and orchestration primitives provided by T for complex, audited analytical workflows.

---

## Table of Contents

- [Dynamic Pattern Branching](#dynamic-pattern-branching)
- [Static DAG Conditionals](#static-dag-conditionals)
- [Model Interchange: ONNX and PMML](#model-interchange-onnx-and-pmml)
- [Composable Lenses (`lens`)](#composable-lenses-lens)
- [Metaprogramming & Quotation](#metaprogramming--quotation)
- [Property-Based Testing (`propcraft`)](#property-based-testing-propcraft)
- [Custom Polyglot Serializers](#custom-polyglot-serializers)
- [Graph Introspection & Auditing](#graph-introspection--auditing)

---

## Dynamic Pattern Branching

For parameter sweeps, cross-validation, and partitioned processing, T provides dynamic branching operators that expand a single node definition into multiple discrete derivations in the Nix dependency graph:

- **`map_pattern(dep)`**: Expands over each element of an upstream List, Vector, or DataFrame partition.
- **`cross_pattern(dep1, dep2)`**: Computes the full Cartesian product across multiple parameters or datasets.

```t
p = pipeline {
  params = node(command = [0.01, 0.05, 0.10, 0.20])

  -- Automatically creates 4 parallel derivations in the Nix graph
  grid_search = pyn(
    pattern = map_pattern(params),
    command = <{
      from sklearn.linear_model import Ridge
      clf = Ridge(alpha = params).fit(X_train, y_train)
      clf.score(X_test, y_test)
    }>,
    deserializer = [params: ^json],
    serializer = ^json
  )
}
```

Branches execute across runtimes (T, R, Python, Julia) and materialize as distinct, content-addressed artifacts in the Nix store.

---

## Static DAG Conditionals

To include or exclude pipeline stages based on environment or configuration without breaking the directed acyclic graph (DAG):

- **`node_when(condition, node_value)`**: Only includes the node in the pipeline if the boolean condition evaluates to true at pipeline construction time.
- **`node_fork(cond1, val1, cond2, val2, ..., .default = ...)`**: Selects the first branch whose condition matches.

```t
p = pipeline {
  heavy_audit = node_when(
    Sys.getenv("ENABLE_AUDIT") == "true",
    rn(command = <{ run_full_regulatory_audit(dataset) }>, deserializer = [dataset: ^ipc])
  )
}
```

Because branch selection happens before graph materialization, Nix build purity and acyclicity are preserved.

---

## Model Interchange: ONNX and PMML

T provides native boundaries for portable machine learning formats:

### 1. ONNX (`^onnx`)
Move models freely between Python (`scikit-learn`, `PyTorch`), Julia (`ONNX.jl`), and R.

```t
-- Train in Python, export to ONNX
model_py = pyn(
  command = <{
    from sklearn.ensemble import RandomForestRegressor
    clf = RandomForestRegressor().fit(X, y)
    clf
  }>,
  serializer = ^onnx
)

-- Score natively in T without a Python runtime:
predictions = node(
  command = <{
    test_X = read_csv("data/test.csv")
    test_X |> mutate($pred = predict(test_X, model_py))
  }>,
  deserializer = [model_py: ^onnx]
)
```

### 2. PMML (`^pmml`)
For GLMs, decision trees, and tree ensembles (Random Forest, XGBoost, LightGBM), T embeds a native C/OCaml PMML scorer. Models trained in R or Python can be evaluated in T without spawning an external process or linking to Python or R at scoring time.

---

## Composable Lenses (`lens`)

The `lens` package provides serializable, functional optics for navigating and transforming deeply nested data structures and pipelines without mutable state:

```t
import "lens" [lens_path, view, set, over]

-- Create a reusable lens targeting a nested configuration field
alpha_lens = lens_path(["models", "ridge", "hyperparameters", "alpha"])

-- Query without mutation:
current_alpha = view(alpha_lens, config)

-- Purely functional update:
updated_config = set(alpha_lens, 0.05, config)

-- Modify via function:
scaled_config = over(alpha_lens, \(a) a * 2.0, config)
```

Lenses also operate on computation graphs, enabling programmatic DAG rewrites and node substitutions.

---

## Metaprogramming & Quotation

T features an explicit metaprogramming subsystem inspired by Scheme and R's non-standard evaluation (NSE):

- **`expr(...)`**: Captures expressions as unevaluated AST data structures.
- **`enquo(arg)`**: Captures user expressions and their lexical environments.
- **`to_symbol("var_name")`**: Converts strings into first-class identifiers.
- **`eval_expr(e, env)`**: Explicitly evaluates quoted expressions.

```t
-- Construct code dynamically
col_sym = to_symbol("salary")
filter_expr = expr($col_sym > 50000)
```

---

## Property-Based Testing (`propcraft`)

For mission-critical calculations, the `propcraft` package provides generative property testing. Rather than asserting individual unit cases, you define invariants over generated input distributions:

```t
import "propcraft" [prop_for_all, prop_gen_int_range, prop_gen_df]

set_seed(42)

-- Invariant: normalized probabilities must sum to 1.0
prop_result = prop_for_all(
  prop_gen_df([
    weights: prop_gen_float_range(0.1, 10.0, size = 20)
  ]),
  \(df) {
    p = df$weights / sum(df$weights)
    abs(sum(p) - 1.0) < 1e-9
  }
)

assert(prop_result)
```

If an assertion fails, `propcraft` automatically applies shrinking strategies to find the minimal counterexample and reproduces it deterministically using the seeded RNG.

---

## Custom Polyglot Serializers

Beyond built-in formats (`^ipc`, `^parquet`, `^csv`, `^json`, `^pmml`, `^onnx`), T allows defining custom serializers directly in pipeline code:

```t
-- Define a YAML serializer with inline language handlers
yaml_serializer = serializer(
  format = "yaml",
  py_writer = <{ lambda obj, path: yaml.dump(obj, open(path, 'w')) }>,
  r_reader  = <{ function(path) yaml::read_yaml(path) }>
)

p = pipeline {
  data_py = pyn(
    command = <{ dict(status = "ok", count = 42) }>,
    serializer: yaml_serializer
  )

  report_r = rn(
    command = <{ print(paste("Status:", data_py$status)) }>,
    deserializer: [ data_py: yaml_serializer ]
  )
}
```

---

## Graph Introspection & Auditing

Pipelines and nodes are first-class, introspectable objects. You can inspect provenance, execution timings, and derivation hashes directly from the REPL or in scripts:

- **`explain(p.node_name)`**: Inspects full derivation metadata, store path, serializer configuration, and dependency graph.
- **`which_nodes(p, predicate)`**: Queries nodes matching specific runtime or property criteria.
- **`errored_nodes(p)`**: Filters the graph to inspect only nodes that failed during build.
- **`read_past_node(p.node_name, which_log = ...)`**: Inspects historical artifacts from previous builds.

# explain

Value introspection and intent blocks.

## Functions

| Function | Description |
|----------|-------------|
| `explain(x)` | Return a dict describing a value's type, structure, and metadata |
| `explain_json(x)` | Return the explanation as a JSON string |
| `intent_fields(i)` | Get the field names from an intent block |
| `intent_get(i, key)` | Get a specific field value from an intent block |

## Intent Blocks

Intent blocks attach metadata to values:

```t
result = data |> summarize(total = sum($amount))

why = intent {
  goal = "Calculate total sales"
  method = "Sum of amount column"
  source = "sales.csv"
}

intent_fields(why)         -- ["goal", "method", "source"]
intent_get(why, "goal")    -- "Calculate total sales"
```

## Examples

```t
explain(42)           -- {type: "Int", value: "42"}
explain([1, 2, 3])    -- {type: "List", length: 3, ...}
explain_json(42)      -- JSON string
```

## Foreign Node Metadata

Computed pipeline nodes (`p.node`) from R, Python, and Julia runtimes carry
a `foreign_meta` dict, populated at build time into a `meta` sidecar file
next to `artifact`/`class` (best effort — the build never fails for it):

```t
e = explain(p.fit)
e.foreign_meta.kind        -- "dataframe", "model", or "other"
e.foreign_meta.dimensions  -- shape as int list, e.g. [32, 11] for frames, [4, 3] for matrices, [3] for vectors
e.foreign_meta.n_obs       -- training rows (models)
e.foreign_meta.n_groups    -- grouping units, e.g. 18 subjects (mixed models)
e.foreign_meta.groups      -- per-group counts, e.g. {Subject: 18} (mixed models)
e.foreign_meta.n_features  -- input count (models)
e.foreign_meta.n_trees     -- tree count (forests, when known)
e.foreign_meta.n_rounds    -- boosting rounds (boosted trees, when known)
e.foreign_meta.n_clusters  -- cluster count (clustering, when known)
e.foreign_meta.n_components -- component count (PCA, when known)
e.foreign_meta.dtype        -- element type, e.g. "float64" (arrays, when known)
e.foreign_meta.method      -- algorithm variant, e.g. hclust linkage (when known)
e.foreign_meta.target      -- response name (when known)
e.foreign_meta.formula     -- full formula (R models, when known)
e.foreign_meta.order       -- [p, d, q] (time-series models, when known)
e.foreign_meta.seasonal_order -- [P, D, Q, m] (seasonal models, when known)
e.foreign_meta.features    -- full feature/column list
e.foreign_meta.metrics     -- free metrics (r_squared, aic, bic, ...)
e.foreign_meta.artifact_size -- artifact size in bytes
```

The tree display shows short `features_preview`/`formula_preview` forms;
dot access on `features`/`formula` returns the full values. Unbuilt nodes
report `foreign_meta` as `NA`.

## Status

Built-in package — included with T by default.

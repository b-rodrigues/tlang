# PMML Tutorial

> A practical guide to moving classical models between R, Python, and T with `^pmml`

PMML is T's interchange format for many classical statistical and tree-based models.
It is useful when you want to:

- train a model in **R** or **Python**
- persist it as a stable artifact
- load it back into **T**
- score it natively with `predict(data, model)`

This tutorial focuses on the workflows that T supports today, including the initial
T-native `t_write_pmml()` pass-through path for PMML artifacts that were already loaded
from disk or a pipeline node.

---

## 1. When to Use PMML

Use `^pmml` when you want a model artifact that can cross runtime boundaries while still
being readable by T's native model tooling.

PMML is a good fit for:

- linear and GLM-style models exported from R
- scikit-learn models that `sklearn2pmml` can represent faithfully
- PMML tree and ensemble artifacts that T can score natively

PMML is **not** a universal model format. If your model family or preprocessing pipeline
cannot be represented faithfully in PMML, prefer `^onnx` or keep scoring in the source
runtime.

---

## 2. Prerequisites

PMML support is polyglot, so the exact requirements depend on where the model is produced
or consumed.

| Workflow | Main Requirements |
|---|---|
| R writes PMML | `r2pmml`, `XML`, `jsonlite`, `jre` |
| Python writes PMML | `sklearn2pmml` or `jpmml-statsmodels`, plus `jre` |
| Python reads PMML | JPMML evaluator via wrapper |
| T reads and scores PMML | built-in `t_read_pmml()` + native evaluator |

When PMML is used inside pipelines, these dependencies should be declared explicitly in
your project configuration so T can build the correct runtime environment.

---

## 3. Your First PMML Workflow

The simplest workflow is:

1. train in another runtime
2. serialize with `^pmml`
3. read the artifact in T
4. score it with `predict()`

```t
p = pipeline {
  model_r = rn(
    command = <{
      data <- read.csv("mtcars.csv")
      lm(mpg ~ wt + hp, data = data)
    }>,
    serializer = ^pmml
  )
}

build_pipeline(p)
model = read_node("model_r")
```

At this point `model` is a T model object reconstructed from the PMML artifact.

You can inspect it with the usual model helpers:

```t
summary(model)
fit_stats(model)
coef(model)
```

---

## 4. Scoring PMML Models Natively in T

Once a PMML model is in T, prediction looks the same as prediction for other supported
model objects:

```t
new_data = read_csv("mtcars_new.csv")
preds = predict(new_data, model)
```

This is the main attraction of PMML in T: training can happen in R or Python, but
downstream prediction, summary, and fit-stat extraction can stay inside the T runtime.

For PMML-imported tree models, random forests, and supported boosted ensembles, this is
already a strong workflow:

```t
forest = t_read_pmml("tests/golden/data/iris_random_forest.pmml")
iris = read_csv("tests/golden/data/iris.csv")
predict(iris, forest)
```

---

## 5. Training in R and Consuming in T

R is the most natural PMML producer for many classical models.

```t
p = pipeline {
  train_df = node(
    command = read_csv("mtcars.csv"),
    serializer = ^csv
  )

  model_r = rn(
    command = <{
      glm(am ~ wt + hp, data = train_df, family = binomial())
    }>,
    deserializer = ^csv,
    serializer = ^pmml
  )

  scored = node(
    command = predict(read_csv("mtcars.csv"), model_r),
    deserializer = ^pmml
  )
}
```

The important part is the boundary:

- the R node **writes** a PMML artifact with `serializer = ^pmml`
- the T node **reads** that artifact with `deserializer = ^pmml`

This keeps the interchange contract explicit.

---

## 6. Training in Python and Consuming in T

Python is a strong fit when your model is supported by `sklearn2pmml` or the JPMML
statsmodels bridge.

```t
p = pipeline {
  model_py = pyn(
    command = <{
      from sklearn.ensemble import RandomForestClassifier
      clf = RandomForestClassifier(random_state = 42)
      clf.fit(X, y)
      clf
    }>,
    serializer = ^pmml
  )

  scored = node(
    command = predict(read_csv("iris.csv"), model_py),
    deserializer = ^pmml
  )
}
```

As with R, the boundary is explicit:

- Python exports PMML
- T deserializes the PMML artifact
- T performs native scoring when the imported model family is supported

If the Python model cannot be represented faithfully in PMML, T should fail explicitly
rather than silently switching to a different interchange story.

---

## 7. Loading PMML Directly from Disk

You can also bypass pipelines and load an existing PMML file manually:

```t
model = t_read_pmml("model.pmml")
summary(model)
```

This is useful when:

- you already have exported PMML artifacts
- you want to inspect or score them interactively
- you want to compare several artifacts in the REPL

---

## 8. Writing PMML from T with `t_write_pmml()`

T now provides an initial native `t_write_pmml()` path, but it is intentionally narrow.

Today, `t_write_pmml()` supports **pass-through copying** of PMML artifacts that were
already loaded into T from:

- `t_read_pmml("path.pmml")`
- `read_node("node_name")` for PMML pipeline outputs

Example:

```t
model = t_read_pmml("model.pmml")
t_write_pmml(model, "model-copy.pmml")
```

This is useful when you want to:

- copy a PMML artifact to a deterministic location
- preserve a pipeline output outside the build cache
- re-materialize a model you inspected in the REPL

### Current Limitation

`t_write_pmml()` does **not** yet export arbitrary native T model objects to fresh PMML
XML. If you construct or fit a model natively in T and then call `t_write_pmml()`, T
should fail explicitly unless the value still carries an original PMML source artifact.

That is deliberate: T currently exposes a safe pass-through path, not a pretend PMML
writer for unsupported cases.

---

## 9. Recommended Workflow Pattern

For now, the safest PMML workflow is:

1. train in R or Python
2. export with `^pmml`
3. read and score in T
4. use `t_write_pmml()` only to preserve or copy existing PMML artifacts

In other words:

- use foreign runtimes as the **PMML producers**
- use T as the **PMML consumer and scorer**
- use `t_write_pmml()` as an **artifact-preservation tool**, not as a general exporter

---

## 10. Troubleshooting

### `read_node()` returns an error about missing PMML dependencies

Make sure the runtime that produced or reads the PMML artifact declares the required
packages in project configuration. PMML support is not implicit magic.

### Python PMML loading fails

Check that `jpmml-evaluator` is available in `[additional-tools]` and that `pyarrow` is available in `[py-dependencies]`. Also ensure the JVM-backed PMML toolchain is correctly provisioned.

### `t_write_pmml()` rejects a model

That usually means the value does not carry a source PMML artifact path. Reload it with
`t_read_pmml()` or obtain it from `read_node()` before calling `t_write_pmml()`.

### Predictions differ from the source runtime

Verify that the model family and preprocessing steps are truly representable in PMML.
The model coefficients are often not the problem; preprocessing fidelity usually is.

---

## 11. Next Steps

Now that you have a PMML workflow in place, continue with:

1. **[Statistical Models](models.md)** — inspect imported models with `summary()`, `fit_stats()`, and `predict()`.
2. **[Pipeline Tutorial](pipeline_tutorial.md)** — build larger multi-node workflows around PMML artifacts.
3. **[Serializers in T](serializers.md)** — understand how `^pmml`, `^onnx`, `^arrow`, and `^json` fit into the broader interchange system.

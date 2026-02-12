# **1️⃣ Core Concept**

The goal: a **single `fit()` interface** for all models, with:

* Data & formula specification
* Model abstraction (GLM, RandomForest, XGBoost, etc.)
* Hyperparameters encapsulated in model constructors
* Optional backend engines for advanced computation (GSL, Stan, LightGBM, XGBoost)
* Consistent output objects (`Model` objects)
* Unified pipeline-friendly API

---

# **2️⃣ Unified `fit()` Signature**

```t
fit(
    data: DataFrame,
    formula: Formula,
    model: Model,           # e.g., glm(...), random_forest(...), xgboost(...)
    engine: string? = null  # optional: override backend implementation
)
```

Notes:

* `model` is **always a constructed object** containing:

  * Model type
  * Family / link (GLM)
  * Hyperparameters (trees, eta, etc.)
* `engine` is optional. Default chosen per model type.
* Hyperparameters are stored in the model object itself.

---

# **3️⃣ Model Constructors**

## **GLM**

```t
glm(
    family: Family,         # e.g., poisson(), gaussian(), binomial()
    link: Link? = null,     # optional: defaults to canonical link
    penalty: float? = 0.0,  # optional regularization
    engine: string? = null   # optional backend (GSL, Stan)
)
```

* `family(link = ...)` pattern keeps family + link together.
* IRLS is default fitting method for GSL engine.
* Bayesian engine (Stan) optional via `engine = "stan"`.

### Examples:

```t
fit(data = df, formula = y ~ x, model = glm(family = poisson()))
fit(data = df, formula = y ~ x, model = glm(family = gaussian(link = identity())))
fit(data = df, formula = y ~ x, model = glm(family = negbin(), penalty = 0.1))
```

---

## **Random Forest**

```t
random_forest(
    ntrees: int = 100,
    max_depth: int? = null,
    min_child_weight: float? = 1.0,
    engine: string? = "xgboost"  # default to XGBoost backend
)
```

* All hyperparameters live here.
* Backend determines actual fitting implementation.
* `engine = "native"` could eventually allow a simple OCaml implementation.

### Example:

```t
fit(
    data = df,
    formula = y ~ x,
    model = random_forest(ntrees = 200, max_depth = 10)
)
```

---

## **XGBoost / LightGBM**

```t
xgboost(
    ntrees: int = 100,
    eta: float = 0.3,
    max_depth: int = 6,
    min_child_weight: float = 1.0,
    subsample: float = 1.0,
    colsample_bytree: float = 1.0,
    engine: string? = "xgboost"
)
```

* Similar interface to random forest for consistency.
* Model object stores all hyperparameters.
* `fit()` calls the backend library automatically.

---

# **4️⃣ Data & Formula**

* Data is **Arrow DataFrame**
* Formula follows R-style notation:

```
y ~ x1 + x2 + x3
```

* `fit()` parses formula into X and y matrices.
* Data types are validated automatically.

---

# **5️⃣ Backend Engines**

### Default engines

| Model              | Default Engine     |
| ------------------ | ------------------ |
| GLM                | GSL (IRLS)         |
| GLM (Bayesian)     | Stan (optional)    |
| RandomForest       | XGBoost            |
| XGBoost / LightGBM | XGBoost / LightGBM |

* Optional `engine` argument allows overriding.
* Engines abstracted behind internal interface:

  * `.fit()`
  * `.predict()`
  * `.summary()` (if meaningful)
* Avoid leaking engine-specific hyperparameter names to users.

---

# **6️⃣ Hyperparameters Strategy**

* All hyperparameters **live inside the model constructor**.
* `fit()` reads them and passes to backend.
* Optional `params` dict allowed for extreme flexibility:

```t
rf = random_forest()
fit(data=df, formula=y~x, model=rf, params={ntrees:500, max_depth:12})
```

* Constructor-based approach is the primary, idiomatic method.
* Enables pipeline-friendly code:

```t
df |> fit(model = random_forest(ntrees=200))
```

---

# **7️⃣ Pipeline-Friendly Design**

* `|>` operator works naturally:

```t
df
  |> group_by(category)
  |> fit(model = glm(family=poisson()))
```

* GLM / tree / XGBoost objects remain compatible with pipeline.
* Predictions also pipeline-compatible:

```t
df
  |> fit(model = glm(family=poisson()))
  |> predict(new_data)
```

---

# **8️⃣ Model Objects & API**

All models return a **unified object**:

```t
class Model:
    type: string          # "glm", "random_forest", etc.
    family: Family?       # optional
    hyperparameters: dict
    backend: string
    fitted_object: backend-specific
```

Methods:

* `predict(model, new_data)`
* `summary(model)` (only meaningful for GLMs)
* `coef(model)` (GLMs)
* `feature_importance(model)` (trees)
* `plot(model)` (optional)

---

# **9️⃣ Extensibility**

* Add new model types easily:

```t
neural_net(hidden=10, activation=relu(), engine="native")
gradient_boosting(ntrees=100, learning_rate=0.1)
```

* Engine abstraction ensures `fit()` API doesn’t break.
* Hyperparameters continue to live in constructor.

---

# **10️⃣ Implementation Steps (Phase Plan)**

### Phase 1: GLM core

1. Implement `glm(family=..., link=...)` constructors.
2. Implement IRLS in GSL backend.
3. Build unified `fit()` parsing formula → X, y.
4. Implement `predict()` and `summary()`.

### Phase 2: Random Forest

1. Decide on XGBoost / LightGBM as backend.
2. Implement `random_forest()` constructor.
3. Integrate `fit()` → backend call, read hyperparameters.
4. Implement `predict()` and `feature_importance()`.

### Phase 3: Extended ML (optional)

1. Add XGBoost / LightGBM / CatBoost constructors.
2. Optional neural nets in “shallow” form.
3. Allow optional Bayesian backend for GLMs via Stan.

### Phase 4: Pipeline & UX

1. Add `|>` operator integration.
2. Add group-by modeling (`group_by |> fit()`).
3. Ensure consistent API for hyperparameters and prediction.
4. Validate defaults, canonical links, and backend selection.

---

✅ **Outcome**

* Minimal core for GLM + trees.
* Hyperparameters cleanly encapsulated.
* Pipeline-friendly and declarative syntax.
* Backend-agnostic for future extensions.
* Extendable to Bayesian inference and advanced ML later.


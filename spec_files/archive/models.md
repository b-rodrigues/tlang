# **Modeling in T**

The T modeling interface is inspired by the **tidyverse** and **tidymodels** philosophy in R. It prioritizes tidy data structures, consistent APIs, and composability via the pipeline operator (`|>`).

## **Core Philosophy**

*   **Models as Objects**: Model functions like `lm()` return structured dictionaries containing coefficients, statistics, and metadata.
*   **Tidy Outputs**: Helper functions like `summary()` and `fit_stats()` convert model results into standard DataFrames for easy downstream processing.
*   **Pipeline First**: The entire modeling workflow is designed to work seamlessly with the `|>` operator.
*   **Decoupled Interface**: Model fitting is separated from inspection and prediction.

---

## **1. Linear Models (`lm`)**

The primary model currently implemented is the Linear Model (`lm`), which performs Ordinary Least Squares (OLS) regression.

### **Signature**
```t
lm(data: DataFrame, formula: Formula)
```

*   **`data`**: An Arrow-backed DataFrame.
*   **`formula`**: A formula specification using the `~` operator (e.g., `y ~ x1 + x2`).

### **Example**
```t
model = mtcars |> lm(mpg ~ wt + hp)
```

---

## **2. Model Inspection**

T provides a set of "tidy" functions to inspect model results, similar to the `broom` package in R.

### **`summary(model)`**
Returns a tidy DataFrame of regression coefficients (equivalent to `broom::tidy`).
*   **Columns**: `term`, `estimate`, `std_error`, `statistic`, `p_value`.

### **`fit_stats(model)`**
Returns a one-row DataFrame containing model-level metadata and goodness-of-fit statistics (equivalent to `broom::glance`).
*   **Columns**: `r_squared`, `adj_r_squared`, `sigma`, `statistic` (F-stat), `p_value`, `df`, `logLik`, `AIC`, `BIC`, `deviance`, `df_residual`, `nobs`.

### **`add_diagnostics(model, data = null)`**
Augments a DataFrame with observation-level diagnostic values (equivalent to `broom::augment`). If `data` is omitted, it defaults to the data used to fit the model.
*   **Added Columns**: `.fitted`, `.resid`, `.hat`, `.sigma`, `.cooksd`, `.std_resid`.

---

## **3. Prediction**

Predictions are performed using the `predict()` function.

### **Signature**
```t
predict(data: DataFrame, model: Model)
```
Returns a **Vector** of predicted values. 

*   **Missing Values**: If predictors in the new data contain `NA`, the corresponding prediction will also be `NA`.
*   **Formula Aware**: `predict()` automatically extracts the required columns from the input DataFrame based on the model's formula.

### **Example**
```t
mtcars 
  |> lm(mpg ~ wt + hp) 
  |> predict(new_data)
```

---

## **4. Cross-Runtime Modeling (R/Python)**

Tlang pipelines allow you to leverage the statistical ecosystems of R or Python for model training while keeping the prediction logic within Tlang. This is achieved using the **PMML (Predictive Model Markup Language)** format as an automated interchange layer.

### **Workflow**

1.  **Define Training Node**: Use the `node()` function with `serializer: "pmml"` to specify that the node result should be saved as PMML.
2.  **Define Prediction Node**: Define a T-runtime node with `deserializer: "pmml"` to automatically load the model object into the T environment.
3.  **Execute in T**: Use the native `predict()` function within the T node to generate predictions from the transferred model.

### **Example Pipeline**
```t
# 1. Load data in T
data = node(
    command = read_csv("data/mtcars.csv"),
    serializer = "arrow"
)

# 2. Train model in R using data from T
model = node(
    command = <{ lm(mpg ~ wt + hp, data = data) }>,
    runtime = "R",
    deserializer = "arrow",
    serializer = "pmml"
)

# 3. Predict in T using model from R and data from Python
preds_node = node(
    command = <{
        predict(data, model)
    }>,
    runtime = "T",
    deserializer = [data: "arrow", model: "pmml"]
)

# Assemble pipeline
p = pipeline {
    data = data
    model = model
    predictions = preds_node
}
```

*Note: Automated PMML interchange is currently focused on **Linear Models**. Support for Generalized Linear Models (GLM) is upcoming.*

---

## **5. Model Object Structure**

The object returned by `lm()` is a dictionary with the following internal keys:

| Key | Type | Description |
| :--- | :--- | :--- |
| `coefficients` | Dict | Named coefficients (e.g., `{"(Intercept)": 30.0, "wt": -5.0}`) |
| `std_errors` | Dict | Standard errors for coefficients |
| `formula` | Formula | The original formula used for fitting |
| `r_squared` | Float | R-squared value |
| `adj_r_squared` | Float | Adjusted R-squared |
| `sigma` | Float | Residual standard error |
| `nobs` | Int | Number of observations used |
| `_tidy_df` | DataFrame | Cached coefficients table for `summary()` |
| `_model_data` | Dict | Cached fit statistics for `fit_stats()` |
| `_original_data` | DataFrame | Pointer to the data used to fit the model |

---

## **Future Extensions (Roadmap)**

While currently centered on OLS linear regression, the modeling architecture is designed to expand into:

1.  **GLMs**: Adding `glm()` with family/link support and expanding PMML import capabilities to include Generalized Linear Models.
2.  **Tree-based Models**: Integration with LightGBM/XGBoost via OCaml bindings.
3.  **Cross-Validation**: Native `vfold_cv()` and `fit_resamples()` support.
4.  **Backend Selection**: Allowing users to specify the computation engine (e.g., `engine: "gsl"`, `engine: "lapack"`).

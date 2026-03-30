# Spec: PMML Tree-Based Models Integration

This document outlines the architecture for integrating PMML tree-based models (Decision Trees, Random Forests, XGBoost, LightGBM) into the $T$ language. It serves as a guide for adding future model types (e.g., CatBoost, AdaBoost) while maintaining consistency.

## 1. Architectural Overview

PMML models are treated as first-class citizens in $T$ via the `t_read_pmml()` function. The integration follows a three-stage pipeline:

1.  **Parsing (`src/pmml_utils.ml`)**: Consumes XML and converts it into a structured OCaml OCaml internal representation.
2.  **Prediction (`src/packages/stats/predict.ml`)**: Evaluates the model against a $T$ DataFrame (`VTable`).
3.  **Statistics (`src/packages/stats/fit_stats.ml`)**: Extracts metadata and "broom-style" tidy metrics from the model.

## 2. Shared Data Structures

Internal model data is stored in the `boosted_model` key of the **model Dict** (a `VDict` object). This generalized structure handles all additive ensembles:

```ocaml
type boosted_ensemble = {
  model_type : string;           (* e.g., "xgboost", "lightgbm" *)
  trees : pmml_tree list;        (* List of individual trees *)
  learning_rate : float;         (* Overall scaling factor *)
  objective : string;            (* "classification" or "regression" *)
  mining_function : string;      (* PMML MiningFunction attribute *)
  rescale_constant : float;      (* Bias/offset, if applicable *)
  rescale_factor : float;        (* Multiplier, if applicable *)
}
```

## 3. Implementation Steps for New Models

To add a new tree-based model (e.g., **CatBoost**):

### Step A: Parser Generalization (`pmml_utils.ml`)
1.  **Algorithm Detection**: Update `read_pmml` to recognize the `algorithmName` attribute in the `<MiningModel>` or `<TreeModel>` tags.
2.  **Tree Flattening**: Ensure the sub-components (Segments) are correctly flattened into the `trees` list.
3.  **Namespace Handling**: $T$ uses a generic XML parser (`xmlm`). If the new model uses custom namespaces, ensure the tag-matching logic is robust.

### Step B: Scaling and Bias (`predict.ml`)
Different frameworks apply "post-processing" to the sum of tree nodes differently:
-   **XGBoost**: Typically requires a logistic function for classification or raw sums for regression.
-   **LightGBM**: Similar, but often uses different sigmoid parameters.
-   **CatBoost**: May have different internal score-to-probability transforms.

Ensure the `predict_boosted_model` function in `predict.ml` accounts for these differences based on the `model_type` field.

### Step C: Tidy Statistics (`fit_stats.ml`)
Register the new model type in the `fit_stats` dispatch logic to provide:
-   `n_trees`
-   `n_features`
-   `model_type`

## 4. Best Practices & Pitfalls

### Case Sensitivity
-   $T$'s `clean_colnames()` function lowercases all names (`Petal.Length` -> `petal_length`).
-   **Rule**: Always train/export models with **lowercase** column names to ensure seamless compatibility with the default $T$ data cleaning pipeline.

### Tiny Datasets
-   Models like LightGBM have high default `min_data_in_leaf` (e.g., 20).
-   When generating test artifacts on small datasets (like `iris` or `mtcars`), ensure these parameters are set to `1` so the resulting PMML actually contains tree splits rather than just global means.

### Golden Tests
Every new model type **must** include:
1.  A generation script (`tests/golden/generate_<model>.R/py`).
2.  Actual exported PMML files in `tests/golden/data/`.
3.  Ground-truth prediction CSVs in `tests/golden/expected/`.
4.  Registration in `test_runner.ml`.

## 5. Future Roadmap
-   **Categorical Encoding**: Native support for PMML `LocalTransformations` (e.g., One-Hot Encoding) before feeding data into tree nodes.
-   **Evaluation Speed**: Move from tree-walking evaluation to a more optimized vectorized path for large DataFrames.

# compare_native_vs_pmml_scores

Compare native T scoring vs JPMML scoring

Validates the T-native implementation of model scoring (e.g. random forest) against the reference JPMML evaluator. Returns a summary of differences.

## Parameters

- **df** (`DataFrame`): The test data.

- **model** (`Dict`): The model dictionary with both native and PMML metadata.


## Returns

A summary containing `n_diffs`, `match` (Bool), and `n_rows`.


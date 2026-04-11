# predict

Model Prediction

Calculates predicted values for a model object. Standardized on JPMML as the sole scoring authority for PMML models. Native OCaml implementation is maintained for linear models and as a validation fallback for trees.

## Parameters

- **data** (`DataFrame`): The new data used for prediction.

- **model** (`Model`): The model object (PMML, ONNX, or T-native).


## Returns

| DataFrame The predicted values. For JPMML-backed PMML models (e.g. classification),

## See Also

[t_read_onnx](t_read_onnx.html), [t_read_pmml](t_read_pmml.html), [lm](lm.html)


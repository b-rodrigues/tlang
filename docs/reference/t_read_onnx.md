# t_read_onnx

Read an ONNX model file

Loads an ONNX model file from disk and returns a model dictionary. The resulting dictionary contains the model type identifier (^onnx) and the file path. This model object can be passed to `predict()` for native T-side inference.

## Parameters

- **path** (`String`): The file path to the .onnx model.


## Returns

A model dictionary for native scoring.


# t_read_onnx

Read an ONNX model file

Loads an ONNX model file from disk and returns a model dictionary. The resulting dictionary contains the model type identifier (^onnx), the file path, input/output names, and model-level metadata. This model object can be passed to `predict()` for native T-side inference.

## Parameters

- **path** (`String`): The file path to the .onnx model.


## Returns

A model dictionary containing:

- `type = ^onnx`
- `path`
- input/output metadata used by `predict()`

## Notes

- Native T scoring uses ONNX Runtime through the OCaml bindings.
- Julia pipeline nodes can consume `^onnx` artifacts with `jl_read_onnx()`, which is backed by `ONNXRunTime.jl`.
- Julia ONNX export is not implemented; `jl_write_onnx()` raises an explicit error instead of falling back silently.

## Example

```t
p = pipeline {
  model = pyn(
    script = "train.py",
    serializer = ^onnx
  )

  score = jl_node(
    command = <{
      session = model
      session
    }>,
    deserializer = ^onnx
  )
}
```

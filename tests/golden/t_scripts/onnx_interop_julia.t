-- tests/golden/t_scripts/onnx_interop_julia.t
-- Test: Julia ONNX interoperability (Read from Python-generated, Write back)

iris = read_csv("tests/golden/data/iris.csv")
X = iris |> select($`Sepal.Length`, $`Sepal.Width`, $`Petal.Length`, $`Petal.Width`)

p = pipeline {
  -- 1. Load an existing ONNX model (trained in Python)
  model_onx = pyn(
    command = <{
import onnx
onx = onnx.load("tests/golden/data/iris_logreg.onnx")
onx
    }>,
    serializer = ^onnx
  )

  -- 2. Predict in Julia using the model
  pred_jl = jln(
    command = <{
      using ONNXRunTime
      # model_onx is an InferenceSession
      
      # Convert DataFrame to Float32 Matrix
      X_mat = Matrix{Float32}(iris_df[!, [:Sepal_Length, :Sepal_Width, :Petal_Length, :Petal_Width]])
      
      inputs = Dict("float_input" => X_mat)
      outputs = model_onx(inputs)
      
      # Return predictions as a Vector (renamed to avoid self-reference)
      pred_out = outputs["label"]
      pred_out
    }>,
    deserializer = [iris_df: iris, model_onx: model_onx],
    serializer = ^arrow
  )

  -- 3. Pass the model through a Julia node to test writing
  model_rewritten = jln(
    command = <{
      import ONNX
      # Use ONNX.jl to load the file again to get a ModelProto
      model_proto = ONNX.load("tests/golden/data/iris_logreg.onnx")
      model_proto
    }>,
    serializer = ^onnx
  )

  -- 4. Verify the rewritten model in Python
  verify_py = pyn(
    command = <{
import onnxruntime as ort
import numpy as np
import pandas as pd

sess = ort.InferenceSession(model_rewritten)
input_name = sess.get_inputs()[0].name
label_name = sess.get_outputs()[0].name

X_test = np.array([[5.1, 3.5, 1.4, 0.2]], dtype=np.float32)
res = sess.run([label_name], {input_name: X_test})
out_df = pd.DataFrame({"label": res[0]})
out_df
    }>,
    deserializer = [model_rewritten: ^onnx],
    serializer = ^arrow
  )
}

populate_pipeline(p, build = true, verbose = 1)

-- Final assertions
jl_preds = read_node("pred_jl")
py_verify = read_node("verify_py")

py_label = py_verify |> pull($label)

print("JL Preds Row Count:", nrow(jl_preds))
print("PY Verify Label:", get(py_label, 1))

assert(nrow(jl_preds) == 150)
assert(get(py_label, 1) == 0)

print("✓ Julia ONNX read/write interop verified with Python")

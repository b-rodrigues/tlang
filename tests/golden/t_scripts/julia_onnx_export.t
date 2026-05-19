p = pipeline {
  export_node = node(command = <{
    using ONNX
    dummy_in = fill(Float32(3.0), 1, 1)
    tape = ONNX.load("tests/golden/data/mtcars_hp_reg.onnx", dummy_in)
    tape
  }>, runtime = Julia, serializer = ^onnx)
}
res = build_pipeline(p)
if (is_error(res)) {
  print("PIPELINE FAILED!")
  print(read_log("export_node"))
  exit(1)
}

-- Read back the exported node's artifact using native ONNX reader
model = read_node("export_node")

df = read_csv("tests/golden/data/mtcars.csv")
X = df |> head(1) |> select($wt)
preds = predict(X, model)

-- Map vector values to a list of dicts (rows)
rows = preds |> map(\(p) [ pred: p ])
result = to_dataframe(rows)
write_csv(result, "tests/golden/t_outputs/julia_onnx_export_predictions.csv")
print("✓ julia ONNX export complete")

-- tests/golden/t_scripts/iris_onnx_logreg_predict.t
-- Test: ONNX Logistic Regression prediction (native T)

model_path = "tests/golden/data/iris_logreg.onnx"

if (!file_exists(model_path)) {
  -- The runner expects "not yet implemented" to mark as skipped
  print("not yet implemented: ONNX model iris_logreg.onnx not found")
} else {
  df = read_csv("tests/golden/data/iris.csv")
  model = t_read_onnx(model_path)

  -- Native prediction
  preds = predict(df, model)

  -- Construct a dataframe row by row
  rows = preds |> map(\(p) [ pred: p ])
  result = dataframe(rows)
  
  write_csv(result, "tests/golden/t_outputs/iris_onnx_logreg_predictions.csv")
  print("✓ iris ONNX logreg predictions complete")
}

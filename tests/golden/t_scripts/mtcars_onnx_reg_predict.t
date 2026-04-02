-- tests/golden/t_scripts/mtcars_onnx_reg_predict.t
-- Test: ONNX Linear Regression prediction (mtcars hp ~ wt)
df = read_csv("tests/golden/data/mtcars.csv")
X = df |> select($wt)

model = t_read_onnx("tests/golden/data/mtcars_hp_reg.onnx")
preds = predict(X, model)

-- Map vector values to a list of dicts (rows)
rows = preds |> map(\(p) [ pred: p ])
result = dataframe(rows)
write_csv(result, "tests/golden/t_outputs/mtcars_onnx_reg_predictions.csv")
print("✓ mtcars ONNX hp~wt predictions complete")

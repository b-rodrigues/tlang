-- tests/golden/t_scripts/iris_onnx_rf_predict.t
-- Test: ONNX Random Forest prediction (Iris)

df = read_csv("tests/golden/data/iris.csv")
X = df |> select($`Sepal.Length`, $`Sepal.Width`, $`Petal.Length`, $`Petal.Width`)

model = t_read_onnx("tests/golden/data/iris_rf.onnx")

-- Native prediction
preds = predict(X, model)

-- map on VVector returns VVector of VList rows
rows = preds |> map(\(p) [ pred: p ])
result = dataframe(rows)

write_csv(result, "tests/golden/t_outputs/iris_onnx_rf_predictions.csv")
print("✓ iris ONNX random forest predictions complete")

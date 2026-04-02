-- tests/golden/t_scripts/iris_onnx_logreg_predict.t
-- Test: ONNX Logistic Regression prediction (native T)

df = read_csv("tests/golden/data/iris.csv")
-- Use backticks for column names with dots
X = df |> select($`Sepal.Length`, $`Sepal.Width`, $`Petal.Length`, $`Petal.Width`)

model = t_read_onnx("tests/golden/data/iris_logreg.onnx")

-- Native prediction (returns VVector of class indices)
preds = predict(X, model)

-- map on VVector returns rows built from Dict values
rows = preds |> map(\(p) [ pred: p ])
result = dataframe(rows)

write_csv(result, "tests/golden/t_outputs/iris_onnx_logreg_predictions.csv")
print("✓ iris ONNX logreg predictions complete")

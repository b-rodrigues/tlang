-- tests/golden/t_scripts/iris_onnx_logreg_predict.t
-- Test: ONNX Logistic Regression prediction (native T)
df = read_csv("tests/golden/data/iris.csv")
-- The model metadata loading
model = t_read_onnx("tests/golden/data/iris_logreg.onnx")

-- Native prediction
preds = predict(df, model)

-- Create a dataframe with predictions to compare with R/Python
result = dataframe(pred = preds)
write_csv(result, "tests/golden/t_outputs/iris_onnx_logreg_predictions.csv")

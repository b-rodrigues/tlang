-- Test: XGBoost PMML prediction (binary classification, sklearn2pmml)

df = read_csv("tests/golden/data/iris.csv")
model = t_read_pmml("tests/golden/data/iris_xgb_bin.pmml")
preds = predict(df, model) |> pull($Species)
result = df |> mutate($pred = preds) |> select($pred)
write_csv(result, "tests/golden/t_outputs/iris_xgb_bin_predictions.csv")
print("✓ xgboost PMML binary predictions complete")

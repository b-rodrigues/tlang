-- Test: scikit-learn RandomForestRegressor PMML prediction

df = read_csv("tests/golden/data/mtcars.csv")
model = t_read_pmml("tests/golden/data/mtcars_sklearn_rf.pmml")
preds = predict(df, model)
result = df |> mutate($pred = preds) |> select($pred)
write_csv(result, "tests/golden/t_outputs/mtcars_sklearn_rf_predictions.csv")
print("✓ sklearn random forest (regression) predictions complete")

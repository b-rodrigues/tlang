-- Test: scikit-learn RandomForestClassifier PMML prediction

df = read_csv("tests/golden/data/iris.csv")
model = t_read_pmml("tests/golden/data/iris_sklearn_rf.pmml")
preds = predict(df, model) |> select($Species)
result = df |> mutate($pred = preds) |> select($pred)
write_csv(result, "tests/golden/t_outputs/iris_sklearn_rf_predictions.csv")
print("✓ sklearn random forest (classification) predictions complete")

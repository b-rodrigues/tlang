-- Test: R randomForest regression PMML prediction

df = read_csv("tests/golden/data/mtcars.csv")
model = t_read_pmml("tests/golden/data/mtcars_random_forest.pmml")
preds = predict(df, model)
result = df |> mutate($pred = preds) |> select($pred)
write_csv(result, "tests/golden/t_outputs/mtcars_random_forest_predictions.csv")
print("✓ randomForest PMML regression predictions complete")

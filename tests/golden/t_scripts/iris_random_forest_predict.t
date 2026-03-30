-- Test: Random Forest PMML prediction (R randomForest)
-- Compares to: R randomForest predictions on iris

df = read_csv("tests/golden/data/iris.csv")
model = t_read_pmml("tests/golden/data/iris_random_forest.pmml")
preds = predict(df, model)
result = dataframe([pred: preds])
write_csv(result, "tests/golden/t_outputs/iris_random_forest_predictions.csv")
print("✓ randomForest PMML predictions complete")

-- Test: XGBoost PMML prediction (regression, sklearn2pmml)

df = read_csv("tests/golden/data/mtcars.csv")
model = t_read_pmml("tests/golden/data/mtcars_xgb_reg.pmml")
preds = predict(df, model)
result = df |> mutate($pred = preds) |> select($pred)
write_csv(result, "tests/golden/t_outputs/mtcars_xgb_reg_predictions.csv")
print("✓ xgboost PMML regression predictions complete")

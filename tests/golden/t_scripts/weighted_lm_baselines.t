-- Test: weighted lm() against R baselines
df = dataframe([
  x: [1, 2, 3, 4],
  y: [1, 2, 2, 4]
])

model = lm(data = df, formula = y ~ x, weights = [1, 1, 2, 2])

result = dataframe([
  intercept: head(model._tidy_df.estimate),
  slope: head(tail(model._tidy_df.estimate)),
  r_squared: model.r_squared,
  sigma: model.sigma
])

write_csv(result, "tests/golden/t_outputs/weighted_lm_baselines.csv")
print("✓ weighted lm baselines complete")

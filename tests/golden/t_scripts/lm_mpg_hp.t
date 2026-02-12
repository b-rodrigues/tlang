-- Test: Extract lm() results for comparison with R
-- Compares to: R's lm(mpg ~ hp, data = mtcars) intercept, slope, and R^2
df = read_csv("tests/golden/data/mtcars.csv")
model = lm(data = df, formula = mpg ~ hp)
coeffs = model._tidy_df.estimate
r_sq = model.r_squared
-- Use head/tail since we don't have list indexing
intercept_val = head(coeffs)
slope_val = head(tail(coeffs))
result = summarize(df, $intercept = intercept_val, $slope = slope_val, $r_squared = r_sq)
write_csv(result, "tests/golden/t_outputs/lm_mpg_hp_simple.csv")
print("✓ lm(mpg ~ hp) complete")

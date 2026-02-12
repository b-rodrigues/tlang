-- Test: Extract lm() coefficients for comparison with R
-- Compares to: R's coef(lm(mpg ~ hp, data = mtcars)) intercept and slope
df = read_csv("tests/golden/data/mtcars.csv")
model = lm(data = df, formula = mpg ~ hp)
coeffs = model._tidy_df.estimate
-- Use head/tail since we don't have list indexing
intercept_val = head(coeffs)
slope_val = head(tail(coeffs))
result = summarize(df, $intercept = intercept_val, $slope = slope_val)
write_csv(result, "tests/golden/t_outputs/lm_mpg_hp_coefficients.csv")
print("✓ lm(mpg ~ hp) coefficients complete")

-- Test: Extract lm() coefficients for comparison with R
-- Compares to: R's coef(lm(mpg ~ hp, data = mtcars)) intercept and slope
df = read_csv("tests/golden/data/mtcars.csv")
model = lm(data = df, formula = mpg ~ hp)
result = summarize(df, "intercept", \(d) model.intercept, "slope", \(d) model.slope)
write_csv(result, "tests/golden/t_outputs/lm_mpg_hp_coefficients.csv")
print("✓ lm(mpg ~ hp) coefficients complete")

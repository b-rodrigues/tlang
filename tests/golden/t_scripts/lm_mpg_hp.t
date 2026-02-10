-- Test: Simple linear regression lm(data = df, formula = mpg ~ hp)
-- Compares to: R's lm(mpg ~ hp, data = mtcars) intercept, slope, r_squared
df = read_csv("tests/golden/data/mtcars.csv")
model = lm(data = df, formula = mpg ~ hp)
result = summarize(df, "intercept", \(d) model.intercept, "slope", \(d) model.slope, "r_squared", \(d) model.r_squared)
write_csv(result, "tests/golden/t_outputs/lm_mpg_hp_simple.csv")
print("✓ lm(mpg ~ hp) simple stats complete")

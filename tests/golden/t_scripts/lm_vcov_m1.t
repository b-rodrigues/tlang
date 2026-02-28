-- Test: vcov() for mpg ~ wt
df = read_csv("tests/golden/data/mtcars.csv")
model = lm(mpg ~ wt, data: df)
v = vcov(model)
write_csv(v, "tests/golden/t_outputs/lm_vcov_m1.csv")
print("✓ lm_vcov_m1 complete")

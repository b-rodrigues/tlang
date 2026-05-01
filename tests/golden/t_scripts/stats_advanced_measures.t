-- Test: advanced statistical measures against R
df = read_csv("tests/golden/data/mtcars.csv")
mpg = df.mpg

res = dataframe([
  skew_mpg: skewness(mpg),
  kurt_mpg: kurtosis(mpg),
  sd_mpg: sd(mpg),
  quantile_mpg_25: quantile(mpg, 0.25),
  quantile_mpg_75: quantile(mpg, 0.75)
])

write_csv(res, "tests/golden/t_outputs/stats_advanced_measures.csv")
print("✓ advanced stats complete")

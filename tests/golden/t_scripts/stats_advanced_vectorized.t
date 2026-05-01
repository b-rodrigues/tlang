-- Test: vectorized advanced statistical measures against R
df = read_csv("tests/golden/data/mtcars.csv")
mpg = df.mpg

res = dataframe([
  winsor_mpg_05: winsorize(mpg, 0.05),
  huber_mpg_2: huber_loss(mpg, 2),
  norm_mpg: normalize(mpg)
])

write_csv(res, "tests/golden/t_outputs/stats_advanced_vectorized.csv")
print("✓ advanced vectorized stats complete")

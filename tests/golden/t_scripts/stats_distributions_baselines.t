-- Test: distribution functions and correlation against R
df = read_csv("tests/golden/data/mtcars.csv")
mpg = df.mpg
hp = df.hp

res = dataframe([
  pnorm_0: pnorm(0.0),
  pnorm_1: pnorm(1.0),
  pnorm_neg1: pnorm(-1.0),
  pt_2_10: pt(2.0, 10),
  pf_3_5_20: pf(3.0, 5, 20),
  pchisq_4_2: pchisq(4.0, 2),
  cor_mpg_hp: cor(mpg, hp)
])

write_csv(res, "tests/golden/t_outputs/stats_distributions_baselines.csv")
print("✓ distributions complete")

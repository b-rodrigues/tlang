-- Test: specialized statistical functions against R
df = read_csv("tests/golden/data/mtcars.csv")

mpg = df.mpg
hp = df.hp

res = dataframe([
  cv_mpg: cv(mpg),
  fivenum_min: get(fivenum(mpg), 0),
  fivenum_q1: get(fivenum(mpg), 1),
  fivenum_med: get(fivenum(mpg), 2),
  fivenum_q3: get(fivenum(mpg), 3),
  fivenum_max: get(fivenum(mpg), 4),
  trimmed_mean_mpg_10: trimmed_mean(mpg, 0.1),
  mad_mpg: mad(mpg),
  iqr_mpg: iqr(mpg),
  range_min: get(range(mpg), 0),
  range_max: get(range(mpg), 1),
  var_mpg: var(mpg),
  cov_mpg_hp: cov(mpg, hp)
])

write_csv(res, "tests/golden/t_outputs/stats_specialized_baselines.csv")
print("✓ specialized stats complete")

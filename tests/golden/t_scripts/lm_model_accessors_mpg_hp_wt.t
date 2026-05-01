-- Test: coef(), conf_int(), sigma(), nobs(), and df_residual() on mpg ~ hp + wt
df = read_csv("tests/golden/data/mtcars.csv")
model = lm(mpg ~ hp + wt, data: df)

ci_95 = conf_int(model)
write_csv(ci_95, "tests/golden/t_outputs/lm_conf_int_mpg_hp_wt.csv")

ci_99 = conf_int(model, 0.99)
write_csv(ci_99, "tests/golden/t_outputs/lm_conf_int99_mpg_hp_wt.csv")

coefs = coef(model)
write_csv(coefs, "tests/golden/t_outputs/lm_coef_mpg_hp_wt.csv")

accessors = dataframe([
  [
    sigma: sigma(model),
    nobs: nobs(model),
    df_residual: df_residual(model)
  ]
])
write_csv(accessors, "tests/golden/t_outputs/lm_model_accessors_mpg_hp_wt.csv")

print("✓ lm_model_accessors_mpg_hp_wt complete")

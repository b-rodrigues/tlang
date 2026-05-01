mtcars = read_csv("tests/golden/data/mtcars.csv")

-- 25.1: fit_stats for lm
m1 = lm(data = mtcars, formula = mpg ~ wt)
m2 = lm(data = mtcars, formula = mpg ~ wt + hp)

fs1 = fit_stats(m1)
write_csv(fs1, "tests/golden/t_outputs/mtcars_fit_stats_m1.csv")

-- 25.2: fit_stats for list of models
fs_multi = fit_stats([M1: m1, M2: m2])
write_csv(fs_multi, "tests/golden/t_outputs/mtcars_fit_stats_multi.csv")

-- 25.3: anova
anova_res = anova(m1 = m1, m2 = m2)
write_csv(anova_res, "tests/golden/t_outputs/mtcars_anova_m1_m2.csv")

-- 25.4: wald_test
wt_res = wald_test(m2, terms = ["wt", "hp"])
write_csv(wt_res, "tests/golden/t_outputs/mtcars_wald_wt_hp.csv")
print("✓ stats_model_comparisons complete")


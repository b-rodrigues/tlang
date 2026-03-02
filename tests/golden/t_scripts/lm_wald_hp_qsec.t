-- Test: wald_test(m2, terms: ["hp", "qsec"]) for joint significance
df = read_csv("tests/golden/data/mtcars.csv")
m2 = lm(mpg ~ wt + hp + qsec, data: df)

wh = wald_test(m2, terms: ["hp", "qsec"])

write_csv(wh, "tests/golden/t_outputs/lm_wald_hp_qsec.csv")
print("success lm_wald_hp_qsec complete")

-- tests/stats/test_anova_wald.t
mtcars = read_csv("tests/golden/data/mtcars.csv")

-- Nested models for ANOVA
m1 = lm(mpg ~ wt, data: mtcars)
m2 = lm(mpg ~ wt + hp + qsec, data: mtcars)

print("--- ANOVA ---")
av = anova(m1, m2)
print(av)

print("--- Wald Test (Joint hp and qsec in m2) ---")
wt = wald_test(m2, terms: ["hp", "qsec"])
print(wt)

print("--- Wald Test (Single term: wt) ---")
wt_single = wald_test(m2, terms: ["wt"])
print(wt_single)

print("--- Distributions ---")
print("pnorm(1.96):")
print(pnorm(1.96))
print("pt(1.96, 100):")
print(pt(1.96, 100))
print("pf(3.0, 2, 30):")
print(pf(3.0, 2, 30))
print("pchisq(3.84, 1):")
print(pchisq(3.84, 1))

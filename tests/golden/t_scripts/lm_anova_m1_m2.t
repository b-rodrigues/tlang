-- Test: anova(m1, m2) comparing mpg ~ wt vs. mpg ~ wt + hp + qsec
df = read_csv("tests/golden/data/mtcars.csv")
m1 = lm(mpg ~ wt, data: df)
m2 = lm(mpg ~ wt + hp + qsec, data: df)

av = anova(m1, m2)

-- Use explicit list for model names
av_result = mutate(av, model: ["m1", "m2"])

write_csv(av_result, "tests/golden/t_outputs/lm_anova_m1_m2.csv")
print("✓ lm_anova_m1_m2 complete")

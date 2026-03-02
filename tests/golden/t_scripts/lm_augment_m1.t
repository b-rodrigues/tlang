-- Test: augment() core columns for mpg ~ wt
df = read_csv("tests/golden/data/mtcars.csv")
model = lm(mpg ~ wt, data: df)
aug = augment(df, model)

-- Select and rename columns to match expected R structure (actual, fitted, resid)
-- Use explicit vector assignment to avoid NameError with $mpg
result = mutate(aug, actual: aug.mpg)
result_final = select(result, $actual, $fitted, $resid)

write_csv(result_final, "tests/golden/t_outputs/lm_augment_m1.csv")
print("success lm_augment_m1 complete")

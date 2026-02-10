-- Test: lead window function on mtcars.mpg
-- Compares to: dplyr::mutate(next_mpg = lead(mpg))
df = read_csv("tests/golden/data/mtcars.csv")
result = mutate(df, "next_mpg", lead(df.mpg))
write_csv(result, "tests/golden/t_outputs/mtcars_lead_mpg.csv")
print("✓ lead(mpg) complete")

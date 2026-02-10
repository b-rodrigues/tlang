-- Test: cumsum window function on mtcars.mpg
-- Compares to: dplyr::mutate(cum_mpg = cumsum(mpg))
df = read_csv("tests/golden/data/mtcars.csv")
result = mutate(df, "cum_mpg", cumsum(df.mpg))
write_csv(result, "tests/golden/t_outputs/mtcars_cumsum_mpg.csv")
print("✓ cumsum(mpg) complete")

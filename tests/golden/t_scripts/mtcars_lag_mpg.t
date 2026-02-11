-- Test: lag window function on mtcars.mpg
-- Compares to: dplyr::mutate(prev_mpg = lag(mpg))
df = read_csv("tests/golden/data/mtcars.csv")
result = mutate(df, $prev_mpg = lag($mpg))
write_csv(result, "tests/golden/t_outputs/mtcars_lag_mpg.csv")
print("✓ lag(mpg) complete")

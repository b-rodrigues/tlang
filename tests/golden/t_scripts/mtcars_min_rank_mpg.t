-- Test: min_rank window function on mtcars.mpg
-- Compares to: dplyr::mutate(rank_mpg = min_rank(mpg))
df = read_csv("tests/golden/data/mtcars.csv")
result = mutate(df, "rank_mpg", min_rank(df.mpg))
write_csv(result, "tests/golden/t_outputs/mtcars_min_rank_mpg.csv")
print("✓ min_rank(mpg) complete")

-- Test: min_rank window function on mtcars.mpg
-- Compares to: dplyr::mutate(rank_mpg = min_rank(mpg))
-- Note: T window functions operate on vectors; column-level mutate not yet supported
df = read_csv("tests/golden/data/mtcars.csv")
-- When column-level mutate is supported:
-- result = df |> mutate("rank_mpg", min_rank(df.mpg))
-- write_csv(result, "tests/golden/t_outputs/mtcars_min_rank_mpg.csv")
print("⚠ window function golden test - column-level mutate not yet supported")

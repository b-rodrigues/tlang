-- Test: cumsum window function on mtcars.mpg
-- Compares to: dplyr::mutate(cum_mpg = cumsum(mpg))
-- Note: T window functions operate on vectors; column-level mutate not yet supported
df = read_csv("tests/golden/data/mtcars.csv")
-- When column-level mutate is supported:
-- result = df |> mutate("cum_mpg", cumsum(df.mpg))
-- write_csv(result, "tests/golden/t_outputs/mtcars_cumsum_mpg.csv")
print("⚠ window function golden test - column-level mutate not yet supported")

-- Test: dense_rank window function on simple.age
-- Compares to: dplyr::mutate(dense_rank_age = dense_rank(age))
-- Note: T window functions operate on vectors; column-level mutate not yet supported
df = read_csv("tests/golden/data/simple.csv")
-- When column-level mutate is supported:
-- result = df |> mutate("dense_rank_age", dense_rank(df.age))
-- write_csv(result, "tests/golden/t_outputs/simple_dense_rank_age.csv")
print("⚠ window function golden test - column-level mutate not yet supported")

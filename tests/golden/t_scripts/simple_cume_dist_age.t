-- Test: cume_dist window function on simple.age
-- Compares to: dplyr::mutate(cume_dist_age = cume_dist(age))
-- Note: T window functions operate on vectors; column-level mutate not yet supported
df = read_csv("tests/golden/data/simple.csv")
-- When column-level mutate is supported:
-- result = df |> mutate("cume_dist_age", cume_dist(df.age))
-- write_csv(result, "tests/golden/t_outputs/simple_cume_dist_age.csv")
print("⚠ window function golden test - column-level mutate not yet supported")

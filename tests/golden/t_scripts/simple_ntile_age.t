-- Test: ntile window function on simple.age
-- Compares to: dplyr::mutate(ntile_age = ntile(age, 4))
-- Note: T window functions operate on vectors; column-level mutate not yet supported
df = read_csv("tests/golden/data/simple.csv")
-- When column-level mutate is supported:
-- result = df |> mutate("ntile_age", ntile(df.age, 4))
-- write_csv(result, "tests/golden/t_outputs/simple_ntile_age.csv")
print("⚠ window function golden test - column-level mutate not yet supported")

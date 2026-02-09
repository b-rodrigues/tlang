-- Test: row_number window function on simple.age
-- Compares to: dplyr::mutate(row_number_age = row_number(age))
-- Note: T window functions operate on vectors; column-level mutate not yet supported
df = read_csv("tests/golden/data/simple.csv")
-- When column-level mutate is supported:
-- result = df |> mutate("row_number_age", row_number(df.age))
-- write_csv(result, "tests/golden/t_outputs/simple_row_number_age.csv")
print("⚠ window function golden test - column-level mutate not yet supported")

-- Test: Select on single row DataFrame
-- Edge case: Ensure select works on DataFrames with exactly 1 row
df = read_csv("tests/golden/data/single_row.csv")
result = df |> select($id, $value)
write_csv(result, "tests/golden/t_outputs/single_row_select.csv")
print("✓ single_row_select complete")

-- Test: Select on empty DataFrame
-- Edge case: Ensure select works on DataFrames with 0 rows
df = read_csv("tests/golden/data/empty.csv")
result = df |> select($col1, $col2)
write_csv(result, "tests/golden/t_outputs/empty_select.csv")
print("✓ empty_select complete")

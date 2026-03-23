-- Test: Filter on empty DataFrame
-- Edge case: Ensure filter works on DataFrames with 0 rows
df = read_csv("tests/golden/data/empty.csv")
result = df |> filter($col1 > 0)
write_csv(result, "tests/golden/t_outputs/empty_filter.csv")
print("✓ empty_filter complete")

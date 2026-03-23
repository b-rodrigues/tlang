-- Test: Mutate on single row DataFrame
-- Edge case: Ensure mutate works on DataFrames with exactly 1 row
df = read_csv("tests/golden/data/single_row.csv")
result = df |> mutate($doubled = $value * 2)
write_csv(result, "tests/golden/t_outputs/single_row_mutate.csv")
print("✓ single_row_mutate complete")

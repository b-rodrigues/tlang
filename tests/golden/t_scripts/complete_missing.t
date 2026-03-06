-- Test: complete
df = read_csv("tests/golden/data/missing_combos.csv")
result = df |> complete($group, $item, fill = [value: 0])
write_csv(result, "tests/golden/t_outputs/complete_missing.csv")
print("✓ complete complete")

-- Test: factor_count
df = to_dataframe([g: to_factor(["a", NA, "a", "b", "b", "c", NA], levels = ["c", "a", "b", "d"]), x: [1, 2, 3, 4, 5, 6, 7]])
res = count(df, $g)
write_csv(res, "tests/golden/t_outputs/factor_count.csv")
print("✓ factor_count complete")

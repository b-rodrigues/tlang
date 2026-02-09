-- Test: Filter with OR condition
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> filter(\(row) row.mpg > 30.0 || row.hp > 200.0)
write_csv(result, "tests/golden/t_outputs/mtcars_filter_mpg_or_hp.csv")
print("✓ filter(mpg > 30 || hp > 200) complete")

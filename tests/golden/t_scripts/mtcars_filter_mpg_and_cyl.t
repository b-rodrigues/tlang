-- Test: Filter with AND condition
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> filter(\(row) row.mpg > 20.0 && row.cyl == 4.0)
write_csv(result, "tests/golden/t_outputs/mtcars_filter_mpg_and_cyl.csv")
print("✓ filter(mpg > 20 && cyl == 4) complete")

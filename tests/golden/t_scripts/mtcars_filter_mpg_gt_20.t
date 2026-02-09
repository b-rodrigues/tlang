-- Test: Filter mpg > 20
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> filter(\(row) row.mpg > 20.0)
write_csv(result, "tests/golden/t_outputs/mtcars_filter_mpg_gt_20.csv")
print("✓ filter(mpg > 20) complete")

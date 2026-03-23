-- Test: Filter with AND condition
df = read_csv("tests/golden/data/mtcars.csv")
-- Filter: mpg > 20 and cyl == 4
result = df |> filter($mpg > 20.0 && $cyl == 4.0)

write_csv(result, "tests/golden/t_outputs/mtcars_filter_mpg_and_cyl.csv")
print("✓ filter(mpg > 20 and cyl == 4) complete")

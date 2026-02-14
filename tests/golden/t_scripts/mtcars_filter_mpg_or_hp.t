-- Test: Filter with OR condition
df = read_csv("tests/golden/data/mtcars.csv")
-- Filter: mpg > 30 or hp > 200
result = df |> filter($mpg > 30.0 || $hp > 200.0)

write_csv(result, "tests/golden/t_outputs/mtcars_filter_mpg_or_hp.csv")
print("✓ filter(mpg > 30 or hp > 200) complete")

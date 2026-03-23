-- Test: Mutate multiple new columns
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> mutate($hp_per_cyl = $hp / $cyl) |> mutate($efficient = $mpg > 20.0)
write_csv(result, "tests/golden/t_outputs/mtcars_mutate_multi.csv")
print("✓ mutate(hp_per_cyl, efficient) complete")

-- Test: Mutate overwrite existing column
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> mutate("mpg", \(row) row.mpg * 1.5)
write_csv(result, "tests/golden/t_outputs/mtcars_mutate_overwrite.csv")
print("✓ mutate(mpg = mpg * 1.5) complete")

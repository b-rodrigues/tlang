-- Test: Mutate simple arithmetic
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> mutate($mpg_double = $mpg * 2.0)
write_csv(result, "tests/golden/t_outputs/mtcars_mutate_double.csv")
print("✓ mutate(mpg_double = mpg * 2) complete")

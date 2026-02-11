-- Test: Mutate ratio of two columns
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> mutate($power_to_weight = $hp / $wt)
write_csv(result, "tests/golden/t_outputs/mtcars_mutate_ratio.csv")
print("✓ mutate(power_to_weight = hp / wt) complete")

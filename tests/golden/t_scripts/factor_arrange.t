-- Test: factor_arrange
df = crossing(size = ["medium", "small", "large"], id = [1, 2])
result = df |> mutate($size_fct = factor($size, levels = ["small", "medium", "large"])) |> arrange($size_fct)
write_csv(result, "tests/golden/t_outputs/factor_arrange.csv")
print("✓ factor_arrange complete")

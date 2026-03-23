-- Test: Division with zeros (Inf handling)
-- Edge case: Division by zero should produce Inf/-Inf as in R
df = read_csv("tests/golden/data/special_values.csv")
result = df |> mutate($result = $value / $divisor)
write_csv(result, "tests/golden/t_outputs/edge_division.csv")
print("✓ edge_division complete")

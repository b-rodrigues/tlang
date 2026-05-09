-- Test: factor_basic
df = read_csv("tests/golden/data/simple.csv")
-- create to_factor with levels reversed to check it doesn't just sort alphabetically
result = df |> mutate($name_fct = to_factor($name, levels = ["Jack", "Iris", "Henry", "Grace", "Frank", "Eve", "David", "Charlie", "Bob", "Alice"]))
write_csv(result, "tests/golden/t_outputs/factor_basic.csv")
print("✓ factor_basic complete")

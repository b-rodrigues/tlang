-- Test: pivot_wider
df = read_csv("tests/golden/data/simple.csv")
result = df |> select($id, $name, $score) |> pivot_wider(names_from = "name", values_from = "score")
write_csv(result, "tests/golden/t_outputs/simple_pivot_wider.csv")
print("✓ pivot_wider complete")

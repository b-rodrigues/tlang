-- Test: pivot_longer
df = read_csv("tests/golden/data/simple.csv")
result = df |> pivot_longer(cols = ["age", "score"], names_to = "measure", values_to = "val")
write_csv(result, "tests/golden/t_outputs/simple_pivot_longer.csv")
print("✓ pivot_longer complete")

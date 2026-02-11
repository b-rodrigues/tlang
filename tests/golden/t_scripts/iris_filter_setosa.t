-- Test: Filter string equality
df = read_csv("tests/golden/data/iris.csv")
result = df |> filter($Species == "setosa")
write_csv(result, "tests/golden/t_outputs/iris_filter_setosa.csv")
print("✓ filter(Species == 'setosa') complete")

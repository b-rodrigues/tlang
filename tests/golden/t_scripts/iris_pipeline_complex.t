-- Test: Complex pipeline
df = read_csv("tests/golden/data/iris.csv")
result = df |> filter($Petal.Length > 1.5) |> mutate($petal_area = $Petal.Length * $Petal.Width) |> group_by($Species) |> summarize($mean_area = mean($petal_area), $count = nrow($petal_area)) |> arrange($mean_area, "desc")
write_csv(result, "tests/golden/t_outputs/iris_pipeline_complex.csv")
print("✓ Complex pipeline complete")

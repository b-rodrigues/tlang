-- Test: Complex pipeline
df = read_csv("tests/golden/data/iris.csv")
result = df |> filter(\(row) row.Petal.Length > 1.5) |> mutate("petal_area", \(row) row.Petal.Length * row.Petal.Width) |> group_by("Species") |> summarize("mean_area", \(group) mean(group.petal_area)) |> join(df |> filter(\(row) row.Petal.Length > 1.5) |> group_by("Species") |> summarize("count", \(group) nrow(group)), "Species") |> arrange("mean_area", "desc")
write_csv(result, "tests/golden/t_outputs/iris_pipeline_complex.csv")
print("✓ Complex pipeline complete")

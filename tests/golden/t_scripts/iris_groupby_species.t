-- Test: Group by on iris dataset
df = read_csv("tests/golden/data/iris.csv")
result = df |> group_by($Species) |> summarize($mean_petal_length = mean($Petal.Length), $mean_petal_width = mean($Petal.Width))
write_csv(result, "tests/golden/t_outputs/iris_groupby_species.csv")
print("✓ group_by(Species) %>% summarize(mean petal dims) complete")

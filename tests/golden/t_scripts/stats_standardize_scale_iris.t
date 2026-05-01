-- Test: standardize() and scale() parity on iris sepal length
iris = read_csv("tests/golden/data/iris.csv")

result = iris |>
  mutate($standardized = standardize($`Sepal.Length`)) |>
  mutate($scaled = scale($`Sepal.Length`)) |>
  select($`Sepal.Length`, $standardized, $scaled)

write_csv(result, "tests/golden/t_outputs/stats_standardize_scale_iris.csv")
print("✓ stats_standardize_scale_iris complete")


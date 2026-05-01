-- Test: skewness(), kurtosis(), and mode() baselines
iris = read_csv("tests/golden/data/iris.csv")

result = dataframe([
  [
    sepal_length_skewness: skewness(iris.Sepal.Length),
    petal_length_kurtosis: kurtosis(iris.Petal.Length),
    skewness_na_rm: skewness([1, 2, NA, 3, 4], na_rm: true),
    kurtosis_na_rm: kurtosis([1, 2, 3, NA, 4, 5], na_rm: true),
    mode_numeric: mode([1, 2, 2, 3, 3, 3, 4])
  ]
])

write_csv(result, "tests/golden/t_outputs/stats_shape_mode_baselines.csv")
print("✓ stats_shape_mode_baselines complete")

-- Test: Reshape 3x4 array
arr = ndarray([[1, 4, 7, 10], [2, 5, 8, 11], [3, 6, 9, 12]])
s = shape(arr)
d = ndarray_data(arr)
result = [
  shape: s |> map(\(n) string(n)) |> join(","),
  data: d |> map(\(n) string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/ndarray_reshape_3x4.csv")
print("✓ ndarray reshape 3x4 complete")

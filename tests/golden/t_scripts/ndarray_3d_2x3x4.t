-- Test: Create 3D NDArray (2x3x4)
arr = ndarray([
  [[1, 7, 13, 19], [3, 9, 15, 21], [5, 11, 17, 23]],
  [[2, 8, 14, 20], [4, 10, 16, 22], [6, 12, 18, 24]]
])
s = shape(arr)
d = ndarray_data(arr)
-- Output: shape and flattened data
result = [
  shape: s |> map(\(n) string(n)) |> join(","),
  data: d |> map(\(n) string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/ndarray_3d_2x3x4.csv")
print("✓ ndarray 3D (2x3x4) complete")

-- Test: Create 2D NDArray (2x3)
arr = ndarray([[1, 2, 3], [4, 5, 6]])
s = shape(arr)
d = ndarray_data(arr)
-- Output: shape and flattened data (row-major order)
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/ndarray_2d_2x3.csv")
print("✓ ndarray 2D (2x3) complete")

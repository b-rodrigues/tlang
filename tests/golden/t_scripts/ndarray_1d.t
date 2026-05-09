-- Test: Create 1D NDArray
arr = ndarray([1, 2, 3, 4, 5])
s = shape(arr)
d = ndarray_data(arr)
-- Output: shape and flattened data
result = [
  shape: s |> map(\(n) to_string(n)) |> str_join(","),
  data: d |> map(\(n) to_string(n)) |> str_join(", ")
]
df = to_dataframe([result])
write_csv(df, "tests/golden/t_outputs/ndarray_1d.csv")
print("✓ ndarray 1D complete")

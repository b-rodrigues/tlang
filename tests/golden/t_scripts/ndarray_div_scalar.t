-- Test: Element-wise division with scalar
arr = ndarray([[1, 3, 5], [2, 4, 6]])
result_arr = arr ./ 2
s = shape(result_arr)
d = ndarray_data(result_arr)
result = [
  shape: s |> map(\(n) string(n)) |> join(","),
  data: d |> map(\(n) string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/ndarray_div_scalar.csv")
print("✓ ndarray div scalar complete")

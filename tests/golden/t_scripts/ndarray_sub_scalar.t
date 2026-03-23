-- Test: Element-wise subtraction with scalar
arr = ndarray([[1, 3, 5], [2, 4, 6]])
result_arr = arr .- 5
s = shape(result_arr)
d = ndarray_data(result_arr)
result = [
  shape: s |> map(\(n) str_string(n)) |> str_join(","),
  data: d |> map(\(n) str_string(n)) |> str_join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/ndarray_sub_scalar.csv")
print("✓ ndarray sub scalar complete")

-- Test: Element-wise addition of two arrays
arr1 = ndarray([[1, 3, 5], [2, 4, 6]])
arr2 = ndarray([[10, 30, 50], [20, 40, 60]])
result_arr = arr1 .+ arr2
s = shape(result_arr)
d = ndarray_data(result_arr)
result = [
  shape: s |> map(\(n) string(n)) |> join(","),
  data: d |> map(\(n) string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/ndarray_add_array.csv")
print("✓ ndarray add array complete")

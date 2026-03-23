-- Test: Reshape array from 3x4 to 2x6
arr = ndarray([[1, 7, 2, 8], [3, 9, 4, 10], [5, 11, 6, 12]])
arr_reshaped = reshape(arr, [2, 6])
s = shape(arr_reshaped)
d = ndarray_data(arr_reshaped)
result = [
  shape: s |> map(\(n) str_string(n)) |> str_join(","),
  data: d |> map(\(n) str_string(n)) |> str_join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/ndarray_reshape_2x6.csv")
print("✓ ndarray reshape 2x6 complete")

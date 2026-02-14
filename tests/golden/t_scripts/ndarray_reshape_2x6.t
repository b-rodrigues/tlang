-- Test: Reshape array from 3x4 to 2x6
arr = ndarray([[1,2,3,4],[5,6,7,8],[9,10,11,12]])
arr_reshaped = reshape(arr, [2, 6])
s = shape(arr_reshaped)
d = ndarray_data(arr_reshaped)
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
write_csv(result, "tests/golden/t_outputs/ndarray_reshape_2x6.csv")
print("✓ ndarray reshape 2x6 complete")

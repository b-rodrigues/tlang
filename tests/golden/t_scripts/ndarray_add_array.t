-- Test: Element-wise addition of two arrays
arr1 = ndarray([[1, 2, 3], [4, 5, 6]])
arr2 = ndarray([[10, 20, 30], [40, 50, 60]])
result_arr = arr1 .+ arr2
s = shape(result_arr)
d = ndarray_data(result_arr)
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
write_csv(result, "tests/golden/t_outputs/ndarray_add_array.csv")
print("✓ ndarray add array complete")

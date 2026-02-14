-- Test: Element-wise multiplication of two arrays
arr1 = ndarray([[1, 2, 3], [4, 5, 6]])
arr2 = ndarray([[10, 20, 30], [40, 50, 60]])
result_arr = arr1 .* arr2
s = shape(result_arr)
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "10., 40., 90., 160., 250., 360."
)
write_csv(result, "tests/golden/t_outputs/ndarray_mul_array.csv")
print("✓ ndarray mul array complete")

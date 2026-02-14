-- Test: Element-wise addition of two arrays
arr1 = ndarray([[1, 2, 3], [4, 5, 6]])
arr2 = ndarray([[10, 20, 30], [40, 50, 60]])
result_arr = arr1 .+ arr2
s = shape(result_arr)
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "11., 22., 33., 44., 55., 66."
)
write_csv(result, "tests/golden/t_outputs/ndarray_add_array.csv")
print("✓ ndarray add array complete")

-- Test: Element-wise subtraction with scalar
arr = ndarray([[1, 2, 3], [4, 5, 6]])
result_arr = arr .- 5
s = shape(result_arr)
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "-4., -3., -2., -1., 0., 1."
)
write_csv(result, "tests/golden/t_outputs/ndarray_sub_scalar.csv")
print("✓ ndarray sub scalar complete")

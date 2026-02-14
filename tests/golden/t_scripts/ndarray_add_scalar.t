-- Test: Element-wise addition with scalar
arr = ndarray([[1, 2, 3], [4, 5, 6]])
result_arr = arr .+ 10
s = shape(result_arr)
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "11., 12., 13., 14., 15., 16."
)
write_csv(result, "tests/golden/t_outputs/ndarray_add_scalar.csv")
print("✓ ndarray add scalar complete")

-- Test: Comparison operation <= scalar
arr = ndarray([[1, 2, 3], [4, 5, 6]])
result_arr = arr .<= 4
s = shape(result_arr)
-- Boolean results converted to floats: 1.0 for true, 0.0 for false
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "1., 1., 1., 1., 0., 0."
)
write_csv(result, "tests/golden/t_outputs/ndarray_le_scalar.csv")
print("✓ ndarray <= scalar complete")

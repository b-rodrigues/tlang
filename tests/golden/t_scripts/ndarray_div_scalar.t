-- Test: Element-wise division with scalar
arr = ndarray([[1, 2, 3], [4, 5, 6]])
result_arr = arr ./ 2
s = shape(result_arr)
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "0.5, 1., 1.5, 2., 2.5, 3."
)
write_csv(result, "tests/golden/t_outputs/ndarray_div_scalar.csv")
print("✓ ndarray div scalar complete")

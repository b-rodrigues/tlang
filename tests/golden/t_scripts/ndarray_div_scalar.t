-- Test: Element-wise division with scalar
arr = ndarray([[1, 2, 3], [4, 5, 6]])
result_arr = arr ./ 2
s = shape(result_arr)
d = ndarray_data(result_arr)
result = List(
  shape = s |> map(\n -> string(n)) |> join(","),
  data = d |> map(\n -> string(n)) |> join(", ")
)
write_csv(result, "tests/golden/t_outputs/ndarray_div_scalar.csv")
print("✓ ndarray div scalar complete")

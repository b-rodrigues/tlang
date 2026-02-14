-- Test: Element-wise multiplication with scalar
arr = ndarray([[1, 2, 3], [4, 5, 6]])
result_arr = arr .* 2
s = shape(result_arr)
d = ndarray_data(result_arr)
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = d |> map(\x -> string(x)) |> join(", ")
)
write_csv(result, "tests/golden/t_outputs/ndarray_mul_scalar.csv")
print("✓ ndarray mul scalar complete")

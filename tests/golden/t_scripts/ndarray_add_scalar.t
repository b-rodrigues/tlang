-- Test: Element-wise addition with scalar
arr = ndarray([[1, 2, 3], [4, 5, 6]])
result_arr = arr .+ 10
s = shape(result_arr)
d = ndarray_data(result_arr)
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
write_csv(result, "tests/golden/t_outputs/ndarray_add_scalar.csv")
print("✓ ndarray add scalar complete")

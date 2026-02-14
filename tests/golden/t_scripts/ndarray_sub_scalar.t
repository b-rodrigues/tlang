-- Test: Element-wise subtraction with scalar
arr = ndarray([[1, 2, 3], [4, 5, 6]])
result_arr = arr .- 5
s = shape(result_arr)
d = ndarray_data(result_arr)
result = List(
  shape = s |> map(\n -> string(n)) |> join(","),
  data = d |> map(\n -> string(n)) |> join(", ")
)
write_csv(result, "tests/golden/t_outputs/ndarray_sub_scalar.csv")
print("✓ ndarray sub scalar complete")

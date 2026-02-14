-- Test: Create 1D NDArray
arr = ndarray([1, 2, 3, 4, 5])
s = shape(arr)
d = ndarray_data(arr)
-- Output: shape and flattened data
result = List(
  shape = s |> map(\n -> string(n)) |> join(","),
  data = d |> map(\n -> string(n)) |> join(", ")
)
write_csv(result, "tests/golden/t_outputs/ndarray_1d.csv")
print("✓ ndarray 1D complete")

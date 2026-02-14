-- Test: Create 1D NDArray
arr = ndarray([1, 2, 3, 4, 5])
s = shape(arr)
-- Output: shape and flattened data
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "1., 2., 3., 4., 5."
)
write_csv(result, "tests/golden/t_outputs/ndarray_1d.csv")
print("✓ ndarray 1D complete")

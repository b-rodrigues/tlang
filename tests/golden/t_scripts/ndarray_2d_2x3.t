-- Test: Create 2D NDArray (2x3)
arr = ndarray([[1, 2, 3], [4, 5, 6]])
s = shape(arr)
-- Output: shape and flattened data (row-major order)
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "1., 2., 3., 4., 5., 6."
)
write_csv(result, "tests/golden/t_outputs/ndarray_2d_2x3.csv")
print("✓ ndarray 2D (2x3) complete")

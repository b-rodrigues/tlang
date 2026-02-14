-- Test: Create 3D NDArray (2x3x4)
arr = ndarray([
  [[1,2,3,4],[5,6,7,8],[9,10,11,12]],
  [[13,14,15,16],[17,18,19,20],[21,22,23,24]]
])
s = shape(arr)
d = ndarray_data(arr)
-- Output: shape and flattened data
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = d |> map(\x -> string(x)) |> join(", ")
)
write_csv(result, "tests/golden/t_outputs/ndarray_3d_2x3x4.csv")
print("✓ ndarray 3D (2x3x4) complete")

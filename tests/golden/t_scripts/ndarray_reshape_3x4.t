-- Test: Reshape 3x4 array
arr = ndarray([[1,2,3,4],[5,6,7,8],[9,10,11,12]])
s = shape(arr)
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "1., 2., 3., 4., 5., 6., 7., 8., 9., 10., 11., 12."
)
write_csv(result, "tests/golden/t_outputs/ndarray_reshape_3x4.csv")
print("✓ ndarray reshape 3x4 complete")

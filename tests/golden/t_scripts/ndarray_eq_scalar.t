-- Test: Comparison operation == scalar
arr = ndarray([[1, 2, 3], [4, 5, 6]])
result_arr = arr .== 4
s = shape(result_arr)
d = ndarray_data(result_arr)
-- Boolean results converted to floats: 1.0 for true, 0.0 for false
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/ndarray_eq_scalar.csv")
print("✓ ndarray == scalar complete")

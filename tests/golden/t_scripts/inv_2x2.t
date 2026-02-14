-- Test: inverse of a 2x2 matrix
m = ndarray([[4, 7], [2, 6]])
inv_m = inv(m)
s = shape(inv_m)
d = ndarray_data(inv_m)
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/inv_2x2.csv")
print("✓ inv 2x2 complete")

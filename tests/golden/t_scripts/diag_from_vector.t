-- Test: diag from vector -> diagonal matrix
v = ndarray([2, 3, 4])
dm = diag(v)
s = shape(dm)
d = ndarray_data(dm)
result = [
  shape: s |> map(\(n) to_string(n)) |> str_join(","),
  data: d |> map(\(n) to_string(n)) |> str_join(", ")
]
df = to_dataframe([result])
write_csv(df, "tests/golden/t_outputs/diag_from_vector.csv")
print("✓ diag from vector complete")

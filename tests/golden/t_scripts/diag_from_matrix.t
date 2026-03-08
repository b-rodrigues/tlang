-- Test: diag from matrix -> vector
m = ndarray([[1, 2], [3, 4]])
dv = diag(m)
s = shape(dv)
d = ndarray_data(dv)
result = [
  shape: s |> map(\(n) str_string(n)) |> str_join(","),
  data: d |> map(\(n) str_string(n)) |> str_join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/diag_from_matrix.csv")
print("✓ diag from matrix complete")

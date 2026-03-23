-- Test: Matrix multiplication with identity
a = ndarray([[1, 3], [2, 4]])
identity = ndarray([[1, 0], [0, 1]])
c = matmul(a, identity)
s = shape(c)
d = ndarray_data(c)
result = [
  shape: s |> map(\(n) str_string(n)) |> str_join(","),
  data: d |> map(\(n) str_string(n)) |> str_join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/matmul_identity.csv")
print("✓ matmul identity complete")

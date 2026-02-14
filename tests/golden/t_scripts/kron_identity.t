-- Test: Kronecker with identity
a = ndarray([[1, 3], [2, 4]])
identity = ndarray([[1, 0], [0, 1]])
c = kron(a, identity)
s = shape(c)
d = ndarray_data(c)
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/kron_identity.csv")
print("✓ kron identity complete")

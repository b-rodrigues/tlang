-- Test: Kronecker product 2x3 ⊗ 2x2
a = ndarray([[1, 3, 5], [2, 4, 6]])
b = ndarray([[1, 3], [2, 4]])
c = kron(a, b)
s = shape(c)
d = ndarray_data(c)
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/kron_2x3_2x2.csv")
print("✓ kron 2x3 ⊗ 2x2 complete")

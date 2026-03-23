-- Test: Kronecker product 2x2
a = ndarray([[1, 3], [2, 4]])
b = ndarray([[0, 6], [5, 7]])
c = kron(a, b)
s = shape(c)
d = ndarray_data(c)
result = [
  shape: s |> map(\(n) str_string(n)) |> str_join(","),
  data: d |> map(\(n) str_string(n)) |> str_join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/kron_2x2.csv")
print("✓ kron 2x2 complete")

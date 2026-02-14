-- Test: Matrix multiplication 2x2
a = ndarray([[1, 2], [3, 4]])
b = ndarray([[5, 6], [7, 8]])
c = matmul(a, b)
s = shape(c)
d = ndarray_data(c)
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/matmul_2x2.csv")
print("✓ matmul 2x2 complete")

-- Test: Matrix multiplication 2x3 × 3x2
a = ndarray([[1, 3, 5], [2, 4, 6]])
b = ndarray([[1, 4], [2, 5], [3, 6]])
c = matmul(a, b)
s = shape(c)
d = ndarray_data(c)
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/matmul_2x3_3x2.csv")
print("✓ matmul 2x3 × 3x2 complete")

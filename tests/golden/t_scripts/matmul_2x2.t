-- Test: Matrix multiplication 2x2
a = ndarray([[1, 3], [2, 4]])
b = ndarray([[5, 7], [6, 8]])
c = matmul(a, b)
s = shape(c)
d = ndarray_data(c)
result = [
  shape: s |> map(\(n) str_string(n)) |> str_join(","),
  data: d |> map(\(n) str_string(n)) |> str_join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/matmul_2x2.csv")
print("✓ matmul 2x2 complete")

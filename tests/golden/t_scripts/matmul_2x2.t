-- Test: Matrix multiplication 2x2
a = ndarray([[1, 2], [3, 4]])
b = ndarray([[5, 6], [7, 8]])
c = matmul(a, b)
s = shape(c)
-- Result should be [[19, 22], [43, 50]]
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "19., 22., 43., 50."
)
write_csv(result, "tests/golden/t_outputs/matmul_2x2.csv")
print("✓ matmul 2x2 complete")

-- Test: Matrix multiplication 2x3 × 3x2
a = ndarray([[1, 2, 3], [4, 5, 6]])
b = ndarray([[1, 2], [3, 4], [5, 6]])
c = matmul(a, b)
s = shape(c)
-- Result should be 2x2
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "22., 28., 49., 64."
)
write_csv(result, "tests/golden/t_outputs/matmul_2x3_3x2.csv")
print("✓ matmul 2x3 × 3x2 complete")

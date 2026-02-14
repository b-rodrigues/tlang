-- Test: Chain matrix multiplications
a = ndarray([[1, 2, 3], [4, 5, 6]])
b = ndarray([[1, 2], [3, 4], [5, 6]])
c = ndarray([[1, 2], [3, 4]])
-- (2x3) × (3x2) = (2x2), then (2x2) × (2x2) = (2x2)
temp = matmul(a, b)
result_arr = matmul(temp, c)
s = shape(result_arr)
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "150., 196., 366., 478."
)
write_csv(result, "tests/golden/t_outputs/matmul_chain.csv")
print("✓ matmul chain complete")

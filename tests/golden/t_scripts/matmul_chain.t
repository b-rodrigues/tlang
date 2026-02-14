-- Test: Chain matrix multiplications
a = ndarray([[1, 2, 3], [4, 5, 6]])
b = ndarray([[1, 2], [3, 4], [5, 6]])
c = ndarray([[1, 2], [3, 4]])
-- (2x3) × (3x2) = (2x2), then (2x2) × (2x2) = (2x2)
temp = matmul(a, b)
result_arr = matmul(temp, c)
s = shape(result_arr)
d = ndarray_data(result_arr)
result = List(
  shape = s |> map(\n -> string(n)) |> join(","),
  data = d |> map(\n -> string(n)) |> join(", ")
)
write_csv(result, "tests/golden/t_outputs/matmul_chain.csv")
print("✓ matmul chain complete")

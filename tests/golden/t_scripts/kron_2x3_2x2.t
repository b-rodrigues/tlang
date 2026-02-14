-- Test: Kronecker product 2x3 ⊗ 2x2
a = ndarray([[1, 2, 3], [4, 5, 6]])
b = ndarray([[1, 2], [3, 4]])
c = kron(a, b)
s = shape(c)
d = ndarray_data(c)
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
write_csv(result, "tests/golden/t_outputs/kron_2x3_2x2.csv")
print("✓ kron 2x3 ⊗ 2x2 complete")

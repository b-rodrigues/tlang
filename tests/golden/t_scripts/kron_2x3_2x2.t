-- Test: Kronecker product 2x3 ⊗ 2x2
a = ndarray([[1, 2, 3], [4, 5, 6]])
b = ndarray([[1, 2], [3, 4]])
c = kron(a, b)
s = shape(c)
-- Result should be 4x6
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "1., 2., 2., 4., 3., 6., 3., 4., 6., 8., 9., 12., 4., 8., 5., 10., 6., 12., 12., 16., 15., 20., 18., 24."
)
write_csv(result, "tests/golden/t_outputs/kron_2x3_2x2.csv")
print("✓ kron 2x3 ⊗ 2x2 complete")

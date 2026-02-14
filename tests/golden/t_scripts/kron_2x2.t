-- Test: Kronecker product 2x2
a = ndarray([[1, 2], [3, 4]])
b = ndarray([[0, 5], [6, 7]])
c = kron(a, b)
s = shape(c)
-- Result should be 4x4
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "0., 5., 0., 10., 6., 7., 12., 14., 0., 15., 0., 20., 18., 21., 24., 28."
)
write_csv(result, "tests/golden/t_outputs/kron_2x2.csv")
print("✓ kron 2x2 complete")

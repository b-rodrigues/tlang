-- Test: Matrix multiplication with identity
a = ndarray([[1, 2], [3, 4]])
identity = ndarray([[1, 0], [0, 1]])
c = matmul(a, identity)
s = shape(c)
d = ndarray_data(c)
result = List(
  shape = s |> map(\n -> string(n)) |> join(","),
  data = d |> map(\n -> string(n)) |> join(", ")
)
write_csv(result, "tests/golden/t_outputs/matmul_identity.csv")
print("✓ matmul identity complete")

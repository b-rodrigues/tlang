-- Test: Kronecker with identity
a = ndarray([[1, 2], [3, 4]])
identity = ndarray([[1, 0], [0, 1]])
c = kron(a, identity)
s = shape(c)
d = ndarray_data(c)
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = d |> map(\x -> string(x)) |> join(", ")
)
write_csv(result, "tests/golden/t_outputs/kron_identity.csv")
print("✓ kron identity complete")

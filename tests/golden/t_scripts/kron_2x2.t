-- Test: Kronecker product 2x2
a = ndarray([[1, 2], [3, 4]])
b = ndarray([[0, 5], [6, 7]])
c = kron(a, b)
s = shape(c)
d = ndarray_data(c)
result = List(
  shape = s |> map(\n -> string(n)) |> join(","),
  data = d |> map(\n -> string(n)) |> join(", ")
)
write_csv(result, "tests/golden/t_outputs/kron_2x2.csv")
print("✓ kron 2x2 complete")

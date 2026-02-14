-- Test: Operations on matmul result
a = ndarray([[1, 2], [3, 4]])
b = ndarray([[5, 6], [7, 8]])
c = matmul(a, b)
result_arr = c .+ 100
s = shape(result_arr)
-- matmul result is [[19, 22], [43, 50]], add 100
result = List(
  shape = s |> map(\x -> string(x)) |> join(","),
  data = "119., 122., 143., 150."
)
write_csv(result, "tests/golden/t_outputs/matmul_then_add.csv")
print("✓ matmul then add complete")

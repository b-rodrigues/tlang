-- Test: Operations on matmul result
a = ndarray([[1, 2], [3, 4]])
b = ndarray([[5, 6], [7, 8]])
c = matmul(a, b)
result_arr = c .+ 100
s = shape(result_arr)
d = ndarray_data(result_arr)
-- matmul result is [[19, 22], [43, 50]], add 100
result = [
  shape: s |> map(\(n) -> string(n)) |> join(","),
  data: d |> map(\(n) -> string(n)) |> join(", ")
]
df = dataframe([result])
write_csv(df, "tests/golden/t_outputs/matmul_then_add.csv")
print("✓ matmul then add complete")

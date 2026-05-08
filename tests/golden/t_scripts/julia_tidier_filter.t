-- tests/golden/t_scripts/julia_tidier_filter.t
df = read_csv("tests/golden/data/julia_simple_data.csv")
res = df |> filter($age > 30)
write_csv(res, "tests/golden/t_outputs/julia_tidier_filter.csv")
print("✓ julia_tidier_filter")

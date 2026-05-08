-- tests/golden/t_scripts/julia_tidier_arrange.t
df = read_csv("tests/golden/data/julia_simple_data.csv")
res = df |> arrange($score, "desc")
write_csv(res, "tests/golden/t_outputs/julia_tidier_arrange.csv")
print("✓ julia_tidier_arrange")

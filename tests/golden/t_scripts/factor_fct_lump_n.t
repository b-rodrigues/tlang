-- Test: fct_lump_n
df = read_csv("tests/golden/data/iris.csv")
res = df |> mutate($species_lump = fct_lump_n($Species, n = 2))
write_csv(res, "tests/golden/t_outputs/factor_fct_lump_n.csv")
print("✓ fct_lump_n complete")

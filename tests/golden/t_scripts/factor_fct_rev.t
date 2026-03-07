-- Test: fct_rev
df = read_csv("tests/golden/data/simple.csv")
res = df |> mutate($name_fct = factor($name), $name_rev = fct_rev($name_fct))
write_csv(res, "tests/golden/t_outputs/factor_fct_rev.csv")
print("✓ fct_rev complete")

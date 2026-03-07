-- Test: fct_collapse
df = read_csv("tests/golden/data/mtcars.csv")
res = df |> mutate($cyl_fct = factor($cyl), $cyl_coll = fct_collapse($cyl_fct, small = "4", large = ["6", "8"]))
write_csv(res, "tests/golden/t_outputs/factor_fct_collapse.csv")
print("✓ fct_collapse complete")

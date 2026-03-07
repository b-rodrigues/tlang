-- Test: fct_reorder
df = read_csv("tests/golden/data/mtcars.csv")
res = df |> mutate($cyl_fct = factor($cyl), $cyl_reord = fct_reorder($cyl_fct, $mpg))
write_csv(res, "tests/golden/t_outputs/factor_fct_reorder.csv")
print("✓ fct_reorder complete")

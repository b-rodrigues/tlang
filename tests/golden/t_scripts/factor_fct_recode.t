-- Test: fct_recode
df = read_csv("tests/golden/data/simple.csv")
res = df |> mutate($name_fct = factor($name), $name_rec = fct_recode($name_fct, ALICE = "Alice", BOB = "Bob"))
write_csv(res, "tests/golden/t_outputs/factor_fct_recode.csv")
print("✓ fct_recode complete")

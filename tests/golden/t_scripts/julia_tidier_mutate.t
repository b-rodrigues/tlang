-- tests/golden/t_scripts/julia_tidier_mutate.t
df = read_csv("tests/golden/data/julia_simple_data.csv")
res = df |> mutate($age_plus_score = $age + $score)
write_csv(res, "tests/golden/t_outputs/julia_tidier_mutate.csv")
print("✓ julia_tidier_mutate")

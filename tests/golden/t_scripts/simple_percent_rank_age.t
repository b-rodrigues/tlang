-- Test: percent_rank window function on simple.age
-- Compares to: dplyr::mutate(pct_rank_age = percent_rank(age))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, $pct_rank_age = percent_rank($age))
write_csv(result, "tests/golden/t_outputs/simple_percent_rank_age.csv")
print("✓ percent_rank(age) complete")

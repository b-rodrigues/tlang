-- Test: min_rank window function on simple.age
-- Compares to: dplyr::mutate(min_rank_age = min_rank(age))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, "min_rank_age", min_rank(df.age))
write_csv(result, "tests/golden/t_outputs/simple_min_rank_age.csv")
print("✓ min_rank(age) complete")

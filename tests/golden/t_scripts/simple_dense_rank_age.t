-- Test: dense_rank window function on simple.age
-- Compares to: dplyr::mutate(dense_rank_age = dense_rank(age))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, "dense_rank_age", dense_rank(df.age))
write_csv(result, "tests/golden/t_outputs/simple_dense_rank_age.csv")
print("✓ dense_rank(age) complete")

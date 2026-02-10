-- Test: cume_dist window function on simple.age
-- Compares to: dplyr::mutate(cume_dist_age = cume_dist(age))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, "cume_dist_age", cume_dist(df.age))
write_csv(result, "tests/golden/t_outputs/simple_cume_dist_age.csv")
print("✓ cume_dist(age) complete")

-- Test: ntile window function on simple.age
-- Compares to: dplyr::mutate(ntile_age = ntile(age, 4))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, $ntile_age = ntile($age, 4))
write_csv(result, "tests/golden/t_outputs/simple_ntile_age.csv")
print("✓ ntile(age, 4) complete")

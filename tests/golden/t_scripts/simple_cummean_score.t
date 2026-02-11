-- Test: cummean window function on simple.score
-- Compares to: dplyr::mutate(cummean_score = cummean(score))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, $cummean_score = cummean($score))
write_csv(result, "tests/golden/t_outputs/simple_cummean_score.csv")
print("✓ cummean(score) complete")

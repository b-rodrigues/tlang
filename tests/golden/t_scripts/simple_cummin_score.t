-- Test: cummin window function on simple.score
-- Compares to: dplyr::mutate(cummin_score = cummin(score))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, $cummin_score = cummin($score))
write_csv(result, "tests/golden/t_outputs/simple_cummin_score.csv")
print("✓ cummin(score) complete")

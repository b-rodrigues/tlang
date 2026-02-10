-- Test: lag window function with offset 2 on simple.score
-- Compares to: dplyr::mutate(prev2_score = lag(score, 2))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, "prev2_score", lag(df.score, 2))
write_csv(result, "tests/golden/t_outputs/simple_lag2_score.csv")
print("✓ lag(score, 2) complete")

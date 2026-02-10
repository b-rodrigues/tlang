-- Test: lag window function on simple.score
-- Compares to: dplyr::mutate(prev_score = lag(score))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, "prev_score", lag(df.score))
write_csv(result, "tests/golden/t_outputs/simple_lag_score.csv")
print("✓ lag(score) complete")

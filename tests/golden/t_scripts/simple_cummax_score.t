-- Test: cummax window function on simple.score
-- Compares to: dplyr::mutate(cummax_score = cummax(score))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, $cummax_score = cummax($score))
write_csv(result, "tests/golden/t_outputs/simple_cummax_score.csv")
print("✓ cummax(score) complete")

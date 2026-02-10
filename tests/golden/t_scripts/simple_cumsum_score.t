-- Test: cumsum window function on simple.score
-- Compares to: dplyr::mutate(cum_score = cumsum(score))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, "cum_score", cumsum(df.score))
write_csv(result, "tests/golden/t_outputs/simple_cumsum_score.csv")
print("✓ cumsum(score) complete")

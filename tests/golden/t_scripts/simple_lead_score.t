-- Test: lead window function on simple.score
-- Compares to: dplyr::mutate(next_score = lead(score))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, $next_score = lead($score))
write_csv(result, "tests/golden/t_outputs/simple_lead_score.csv")
print("✓ lead(score) complete")

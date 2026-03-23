-- Test: lead window function with offset 2 on simple.score
-- Compares to: dplyr::mutate(next2_score = lead(score, 2))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, $next2_score = lead($score, 2))
write_csv(result, "tests/golden/t_outputs/simple_lead2_score.csv")
print("✓ lead(score, 2) complete")

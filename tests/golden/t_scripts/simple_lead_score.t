-- Test: lead window function on simple.score
-- Compares to: dplyr::mutate(next_score = lead(score))
-- Note: T window functions operate on vectors; column-level mutate not yet supported
df = read_csv("tests/golden/data/simple.csv")
-- When column-level mutate is supported:
-- result = df |> mutate("next_score", lead(df.score))
-- write_csv(result, "tests/golden/t_outputs/simple_lead_score.csv")
print("⚠ window function golden test - column-level mutate not yet supported")

-- Test: cumall and cumany window functions on simple dataset
-- Compares to: dplyr::mutate(cumall_high = cumall(score > 85), cumany_high = cumany(score > 85))
-- Note: T window functions operate on vectors; column-level mutate not yet supported
df = read_csv("tests/golden/data/simple.csv")
-- When column-level mutate is supported:
-- result = df |> mutate("high_score", \(row) row.score > 85)
--            |> mutate("cumall_high", cumall(result.high_score))
--            |> mutate("cumany_high", cumany(result.high_score))
-- write_csv(result, "tests/golden/t_outputs/simple_cumall_cumany.csv")
print("⚠ window function golden test - column-level mutate not yet supported")

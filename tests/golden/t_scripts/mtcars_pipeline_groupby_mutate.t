-- Test: Pipeline group_by %>% mutate (window function)
-- Note: This requires grouped mutate support (group-aware row transformations)
-- Window functions (row_number, lag, cumsum, etc.) are implemented,
-- but group_by |> mutate with group context is not yet supported.
df = read_csv("tests/golden/data/mtcars.csv")
-- When grouped mutate is supported:
-- result = df |> group_by("cyl") |> mutate("mpg_vs_cyl_avg", \(row, group) row.mpg - mean(group.mpg))
-- For now, skip this test
print("⚠ group_by %>% mutate (grouped window) - not yet implemented")

-- Test: Pipeline group_by %>% mutate (window function)
-- Note: This requires window function support which may not be implemented yet
df = read_csv("tests/golden/data/mtcars.csv")
-- This is a placeholder for when window functions are implemented
-- result = df |> group_by("cyl") |> mutate("mpg_vs_cyl_avg", \(row, group) row.mpg - mean(group.mpg))
-- For now, skip this test
print("⚠ group_by %>% mutate (window) - not yet implemented")

-- Test: Pipeline group_by %>% mutate (window function)
-- Compares to: mtcars %>% group_by(cyl) %>% mutate(mpg_vs_cyl_avg = mpg - mean(mpg)) %>% ungroup()
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> group_by("cyl") |> mutate("mpg_vs_cyl_avg", \(g) mean(g.mpg))
-- The R expected has mpg_vs_cyl_avg = mpg - mean(mpg) per group.
-- We compute mean per group, then subtract row-by-row.
-- Step 1: get group means via grouped mutate
step1 = df |> group_by("cyl") |> mutate("cyl_mean_mpg", \(g) mean(g.mpg))
-- Step 2: compute difference with ungrouped mutate
result = step1 |> mutate("mpg_vs_cyl_avg", \(row) row.mpg - row.cyl_mean_mpg)
-- Step 3: drop intermediate column by selecting all original cols + result col
result = result |> select("car_name", "mpg", "cyl", "disp", "hp", "drat", "wt", "qsec", "vs", "am", "gear", "carb", "mpg_vs_cyl_avg")
write_csv(result, "tests/golden/t_outputs/mtcars_pipeline_groupby_mutate.csv")
print("✓ group_by(cyl) %>% mutate(mpg_vs_cyl_avg = mpg - mean(mpg)) complete")

-- Test: Group by with multiple aggregations
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> group_by($cyl) |> summarize($mean_mpg = mean($mpg), $mean_hp = mean($hp), $count = nrow($mpg))
write_csv(result, "tests/golden/t_outputs/mtcars_groupby_cyl_multi_agg.csv")
print("✓ group_by(cyl) %>% summarize(mean_mpg, mean_hp, count) complete")

-- Test: Group by with multiple aggregations
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> group_by("cyl") |> summarize("mean_mpg", \(group) mean(group.mpg)) |> join(df |> group_by("cyl") |> summarize("mean_hp", \(group) mean(group.hp)), "cyl") |> join(df |> group_by("cyl") |> summarize("count", \(group) nrow(group)), "cyl")
write_csv(result, "tests/golden/t_outputs/mtcars_groupby_cyl_multi_agg.csv")
print("✓ group_by(cyl) %>% summarize(mean_mpg, mean_hp, count) complete")

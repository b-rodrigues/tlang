-- Test: Group by with various aggregations
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> group_by("cyl") |> summarize("min_mpg", \(group) min(group.mpg)) |> join(df |> group_by("cyl") |> summarize("max_mpg", \(group) max(group.mpg)), "cyl") |> join(df |> group_by("cyl") |> summarize("sd_mpg", \(group) sd(group.mpg)), "cyl") |> join(df |> group_by("cyl") |> summarize("count", \(group) nrow(group)), "cyl")
write_csv(result, "tests/golden/t_outputs/mtcars_groupby_various_aggs.csv")
print("✓ group_by(cyl) %>% summarize(min, max, sd, n) complete")

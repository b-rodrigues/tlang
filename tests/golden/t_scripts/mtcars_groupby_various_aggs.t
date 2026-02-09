-- Test: Group by with various aggregations
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> group_by("cyl") |> summarize("min_mpg", \(group) min(group.mpg), "max_mpg", \(group) max(group.mpg), "sd_mpg", \(group) sd(group.mpg), "count", \(group) nrow(group))
write_csv(result, "tests/golden/t_outputs/mtcars_groupby_various_aggs.csv")
print("✓ group_by(cyl) %>% summarize(min, max, sd, n) complete")

-- Test: Group by with various aggregations
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> group_by($cyl) |> summarize($min_mpg = min($mpg), $max_mpg = max($mpg), $sd_mpg = sd($mpg), $count = nrow($mpg))
write_csv(result, "tests/golden/t_outputs/mtcars_groupby_various_aggs.csv")
print("✓ group_by(cyl) %>% summarize(min, max, sd, n) complete")

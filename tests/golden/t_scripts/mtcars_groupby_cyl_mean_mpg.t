-- Test: Group by with mean
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> group_by($cyl) |> summarize($mean_mpg = mean($mpg))
write_csv(result, "tests/golden/t_outputs/mtcars_groupby_cyl_mean_mpg.csv")
print("✓ group_by(cyl) %>% summarize(mean(mpg)) complete")

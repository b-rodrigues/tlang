-- Test: Group by multiple columns
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> group_by($cyl, $gear) |> summarize($avg_mpg = mean($mpg))
write_csv(result, "tests/golden/t_outputs/mtcars_groupby_cyl_gear.csv")
print("✓ group_by(cyl, gear) %>% summarize(avg_mpg) complete")

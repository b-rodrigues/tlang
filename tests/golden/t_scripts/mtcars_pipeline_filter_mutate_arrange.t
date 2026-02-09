-- Test: Pipeline filter %>% mutate %>% arrange
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> filter(\(row) row.cyl == 6.0) |> mutate("efficiency", \(row) row.mpg / row.hp * 1000.0) |> arrange("efficiency", "desc")
write_csv(result, "tests/golden/t_outputs/mtcars_pipeline_filter_mutate_arrange.csv")
print("✓ filter %>% mutate %>% arrange complete")

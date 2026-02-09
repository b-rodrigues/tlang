-- Test: Pipeline select %>% filter %>% arrange
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> select("car_name", "mpg", "hp") |> filter(\(row) row.hp > 100.0) |> arrange("mpg", "desc")
write_csv(result, "tests/golden/t_outputs/mtcars_pipeline_select_filter_arrange.csv")
print("✓ select %>% filter %>% arrange complete")

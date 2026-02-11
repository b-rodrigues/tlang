-- Test: Pipeline filter %>% select
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> filter($mpg > 20.0) |> select($car_name, $mpg, $cyl)
write_csv(result, "tests/golden/t_outputs/mtcars_pipeline_filter_select.csv")
print("✓ filter(mpg > 20) %>% select(...) complete")

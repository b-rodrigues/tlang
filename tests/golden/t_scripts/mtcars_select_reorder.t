-- Test: Select with reordering
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> select("hp", "mpg", "car_name")
write_csv(result, "tests/golden/t_outputs/mtcars_select_reorder.csv")
print("✓ select(hp, mpg, car_name) complete")

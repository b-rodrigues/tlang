-- Test: Select multiple columns
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> select($car_name, $mpg, $cyl, $hp)
write_csv(result, "tests/golden/t_outputs/mtcars_select_multi.csv")
print("✓ select(car_name, mpg, cyl, hp) complete")

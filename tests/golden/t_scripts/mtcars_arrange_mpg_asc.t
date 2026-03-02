-- Test: Arrange ascending
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> arrange($mpg, "asc")
write_csv(result, "tests/golden/t_outputs/mtcars_arrange_mpg_asc.csv")
print("success arrange(mpg) complete")

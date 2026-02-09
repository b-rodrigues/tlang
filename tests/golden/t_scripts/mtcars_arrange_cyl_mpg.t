-- Test: Arrange multi-column
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> arrange("cyl", "asc") |> arrange("mpg", "desc")
write_csv(result, "tests/golden/t_outputs/mtcars_arrange_cyl_mpg.csv")
print("✓ arrange(cyl, desc(mpg)) complete")

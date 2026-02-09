-- Test: Arrange descending
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> arrange("mpg", "desc")
write_csv(result, "tests/golden/t_outputs/mtcars_arrange_mpg_desc.csv")
print("✓ arrange(desc(mpg)) complete")

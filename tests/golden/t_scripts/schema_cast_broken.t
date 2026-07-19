pipeline {
  source = read_csv("tests/golden/data/mtcars.csv")
  broken = source |> some_custom_unrecognized_verb()
  clean = broken
    |> mutate(mpg = as.int(1))
    |> expect(columns = ["mpg"], mpg ~ string())
}

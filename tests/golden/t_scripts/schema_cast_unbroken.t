pipeline {
  source = read_csv("tests/golden/data/mtcars.csv")
  clean = source
    |> expect(columns = ["mpg"], mpg ~ string())
}

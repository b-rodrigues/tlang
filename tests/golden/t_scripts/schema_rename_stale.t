-- skip: structural test (pipeline definition, tested by t_check unit tests)
pipeline {
  source = read_csv("tests/golden/data/mtcars.csv")
  renamed = source |> rename(mpg2 = $mpg) |> filter($mpg > 20)
}

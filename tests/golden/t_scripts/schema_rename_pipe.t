-- skip: structural test (pipeline definition, tested by t_check unit tests)
pipeline {
  data_source = read_csv("tests/golden/data/mtcars.csv")
  renamed = data_source |> rename(mpg2 = $mpg) |> select($mpg2)
}

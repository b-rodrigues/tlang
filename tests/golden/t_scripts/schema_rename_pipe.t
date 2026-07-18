pipeline {
  source = read_csv("tests/golden/data/mtcars.csv")
  renamed = source |> rename(mpg2 = $mpg) |> select($mpg2)
}

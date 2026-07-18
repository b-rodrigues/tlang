pipeline {
  data = rn(
    command = <{ library(ggplot2); mtcars }>,
    functions = []
  )
}

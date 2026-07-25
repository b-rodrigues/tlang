-- skip: structural test (pipeline definition, not executable)
pipeline {
  data = rn(
    command = <{ library(ggplot2); mtcars }>,
    functions = []
  )
}

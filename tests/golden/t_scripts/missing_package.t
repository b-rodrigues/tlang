pipeline {
  data = rn(
    command = <{ library(meadowlark); mtcars },
    functions = []
  )
}

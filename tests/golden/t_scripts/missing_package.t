pipeline {
  data = rn(
    command = <{ library(xyzzy_nonexistent_pkg); mtcars },
    functions = []
  )
}

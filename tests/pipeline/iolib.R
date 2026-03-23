# tests/pipeline/iolib.R

r_read_csv <- function(path) {
  readr::read_csv(path, show_col_types = FALSE)
}

r_write_csv <- function(df, path) {
  readr::write_csv(df, path)
}

# Tests for inspect_pipeline().
# Runs under `R CMD check` (via `library(tlang)`) and via
# `Rscript r-package/tests/test_inspect_pipeline.R` from the repository root
# inside `nix develop`.

library(tlang)

td <- tempfile()
dir.create(td, recursive = TRUE)
pipe <- file.path(td, "_pipeline")
dir.create(pipe)

art <- file.path(td, "a.txt")
writeBin(charToRaw("a"), art)

mk_entry <- function(node, runtime, serializer, deps, status = NULL, success = NULL, class = "String") {
  entry <- list(
    node = node,
    path = art,
    runtime = runtime,
    serializer = serializer,
    dependencies = as.list(deps),
    class = class
  )
  if (!is.null(status)) {
    entry$status <- status
  }
  if (!is.null(success)) {
    entry$success <- success
  }
  entry
}

jsonlite::write_json(
  list(nodes = list(
    mk_entry("a", "T", "text", c(), status = "Completed"),
    mk_entry("b", "R", "json", c("a"), success = TRUE),
    mk_entry("c", "Python", "csv", c("b"), success = "false"),
    mk_entry("d", "Julia", "default", c())
  )),
  file.path(pipe, "build_log_20260101_000000_abc.json"),
  auto_unbox = TRUE
)

tbl <- inspect_pipeline(pipeline_dir = pipe)
stopifnot(identical(tbl$node, c("a", "b", "c", "d")))
stopifnot(identical(tbl$status, c("Completed", "Completed", "SoftFailed", NA_character_)))
stopifnot(identical(tbl$depends[[2L]], "a"))
stopifnot(identical(tbl$runtime[[1L]], "T"))
stopifnot(grepl("a.txt$", tbl$path[[1L]]))
cat("build status ok\n")

# which_log selection.
entry <- mk_entry("a", "R", "text", c(), status = "Completed")
jsonlite::write_json(
  list(nodes = list(entry)),
  file.path(pipe, "build_log_20260102_000000_zzz.json"),
  auto_unbox = TRUE
)
stopifnot(identical(inspect_pipeline(pipeline_dir = pipe)$runtime[[1L]], "R"))
stopifnot(identical(inspect_pipeline(pipeline_dir = pipe, which_log = "20260101")$runtime[[1L]], "T"))
cat("which_log ok\n")

# DAG fallback when unbuilt.
td2 <- tempfile()
dir.create(td2, recursive = TRUE)
pipe2 <- file.path(td2, "_pipeline")
dir.create(pipe2)
jsonlite::write_json(
  list(
    list(node_name = "a", depends = list()),
    list(node_name = "b", depends = list("a"))
  ),
  file.path(pipe2, "dag.json"),
  auto_unbox = TRUE
)
fallback <- inspect_pipeline(pipeline_dir = pipe2)
stopifnot(identical(fallback$node, c("a", "b")))
stopifnot(all(fallback$status == "unbuilt"))
stopifnot(identical(fallback$depends[[2L]], "a"))
cat("dag fallback ok\n")

cat("ALL INSPECT TESTS PASSED\n")

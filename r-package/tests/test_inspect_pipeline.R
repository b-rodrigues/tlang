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
stopifnot(identical(tbl$dependencies[[2L]], "a"))
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
stopifnot(identical(fallback$dependencies[[2L]], "a"))
cat("dag fallback ok\n")

# pipeline_overview: name column, failed first, error fields, filters.
err_art <- file.path(td, "err.json")
writeLines('{"type":"VError","code":"RuntimeError","message":"boom"}', err_art)
overview_nodes <- list(
  list(node = "ok", path = art, runtime = "T", serializer = "text",
       dependencies = list(), status = "Completed", class = "String"),
  list(node = "bad", path = err_art, runtime = "T", serializer = "text",
       dependencies = list(), status = "Completed", class = "VError"),
  list(node = "skip", path = art, runtime = "R", serializer = "json",
       dependencies = list(), status = "Skipped", class = "String"),
  list(node = "soft", path = art, runtime = "Python", serializer = "csv",
       dependencies = list(), status = "SoftFailed", class = "String",
       error_code = "ValueError", error_message = "bad value")
)
jsonlite::write_json(
  list(nodes = overview_nodes),
  file.path(pipe, "build_log_20260103_000000_ovw.json"),
  auto_unbox = TRUE
)

overview <- pipeline_overview(pipeline_dir = pipe, which_log = "20260103")
stopifnot("name" %in% names(overview))
stopifnot(!"node" %in% names(overview))
stopifnot(identical(overview$name, c("bad", "soft", "ok", "skip")))
stopifnot(identical(overview$status, c("Errored", "Errored", "Built", "Skipped")))
stopifnot(identical(overview$class, c("Error", "Error", "String", "String")))
stopifnot(identical(overview$error_code, c("RuntimeError", "ValueError", NA_character_, NA_character_)))
stopifnot(identical(overview$error_message, c("boom", "bad value", NA_character_, NA_character_)))
stopifnot(is.na(overview$path[[1L]]))
stopifnot(identical(overview$dependencies[[1L]], character(0)))
cat("pipeline_overview parity ok\n")

stopifnot(identical(pipeline_overview(pipe, "20260103", only = "failed")$name, c("bad", "soft")))
stopifnot(identical(pipeline_overview(pipe, "20260103", only = "built")$name, "ok"))
stopifnot(identical(pipeline_overview(pipe, "20260103", only = "unbuilt")$name, "skip"))
stopifnot(nrow(pipeline_overview(pipe, "20260103", only = "all")) == 4L)
stopifnot(inherits(try(pipeline_overview(pipe, only = "bad"), silent = TRUE), "try-error"))
stopifnot(inherits(try(pipeline_overview(pipe, only = 1), silent = TRUE), "try-error"))
cat("pipeline_overview filters ok\n")

cat("ALL INSPECT PIPELINE TESTS PASSED\n")

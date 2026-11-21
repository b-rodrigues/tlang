# Tests for pipeline_to_frame() and pipeline_config_to_frame().
# Runs under `R CMD check` (via `library(tlang)`) and via
# `Rscript r-package/tests/test_pipeline_frames.R` from the repository root
# inside `nix develop`.

library(tlang)

td <- tempfile()
dir.create(td, recursive = TRUE)
pipe <- file.path(td, "_pipeline")
dir.create(pipe)

art <- file.path(td, "a.txt")
writeBin(charToRaw("a"), art)

mk_entry <- function(node, runtime, serializer, deps, source = NULL, script = NULL) {
  entry <- list(
    node = node, path = art, runtime = runtime, serializer = serializer,
    dependencies = as.list(deps), status = "Completed", class = "String"
  )
  if (!is.null(source)) entry$source <- source
  if (!is.null(script)) entry$script <- script
  entry
}

jsonlite::write_json(
  list(nodes = list(
    mk_entry("a", "T", "text", c(), source = "[1, 2]"),
    mk_entry("b", "R", "json", c("a"), script = "train.R"),
    mk_entry("c", "Python", "csv", c("b"))
  )),
  file.path(pipe, "build_log_20260101_000000_abc.json"),
  auto_unbox = TRUE
)

tbl <- pipeline_to_frame(pipeline_dir = pipe)
stopifnot(identical(tbl$name, c("a", "b", "c")))
stopifnot(identical(tbl$depth, c(0L, 1L, 2L)))
stopifnot(identical(tbl$command_type, c("command", "script", NA_character_)))
stopifnot(identical(tbl$deps[[2L]], "a"))
stopifnot(identical(tbl$runtime[[2L]], "R"))
# Build logs never store these: always NA, never faked.
stopifnot(all(is.na(tbl$deserializer)) && all(is.na(tbl$noop)))
cat("pipeline_to_frame ok\n")

cfg <- pipeline_config_to_frame(pipeline_dir = pipe)
stopifnot(identical(cfg$name, c("a", "b", "c")))
stopifnot(identical(cfg$n_deps, c(0L, 1L, 1L)))
stopifnot(identical(cfg$depth, c(0L, 1L, 2L)))
# Unknown provenance stays NA (unknown, not zero).
stopifnot(all(is.na(cfg$prov_serializer)) && all(is.na(cfg$shell)))
stopifnot(all(is.na(cfg$n_funcs)) && all(is.na(cfg$n_deps_global)))
cat("pipeline_config_to_frame ok\n")

# which_log selection.
entry <- mk_entry("a", "R", "text", c(), source = "x")
jsonlite::write_json(
  list(nodes = list(entry)),
  file.path(pipe, "build_log_20260102_000000_zzz.json"),
  auto_unbox = TRUE
)
stopifnot(identical(pipeline_to_frame(pipeline_dir = pipe)$runtime[[1L]], "R"))
stopifnot(identical(
  pipeline_to_frame(pipeline_dir = pipe, which_log = "20260101")$runtime[[1L]], "T"))
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
fallback <- pipeline_to_frame(pipeline_dir = pipe2)
stopifnot(identical(fallback$name, c("a", "b")))
stopifnot(identical(fallback$depth, c(0L, 1L)))
stopifnot(all(is.na(fallback$runtime)) && all(is.na(fallback$command_type)))
cfg2 <- pipeline_config_to_frame(pipeline_dir = pipe2)
stopifnot(identical(cfg2$n_deps, c(0L, 1L)))
stopifnot(all(is.na(cfg2$serializer)))
cat("dag fallback ok\n")

cat("ALL PIPELINE FRAME TESTS PASSED\n")

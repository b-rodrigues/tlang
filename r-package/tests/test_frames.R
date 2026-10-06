# Tests for list_logs(), build_log_to_frame(), collect_exceptions().
# Runs under `R CMD check` (via `library(tlang)`) and via
# `Rscript r-package/tests/test_frames.R` from the repository root
# inside `nix develop`.

library(tlang)

td <- tempfile()
dir.create(td, recursive = TRUE)
pipe <- file.path(td, "_pipeline")
dir.create(pipe)

art <- file.path(td, "a.txt")
writeBin(charToRaw("a"), art)

mk_entry <- function(node, ...) {
  entry <- list(node = node, path = art, class = "String")
  dots <- list(...)
  for (nm in names(dots)) {
    entry[[nm]] <- dots[[nm]]
  }
  entry
}

jsonlite::write_json(
  list(pipeline = "demo", nodes = list(
    mk_entry("a", runtime = "T", serializer = "text", dependencies = list(),
      status = "Completed", duration = 1.5),
    mk_entry("b", runtime = "R", serializer = "json", dependencies = list("a"),
      success = TRUE, duration = "2"),
    mk_entry("c", runtime = "Python", serializer = "csv", dependencies = list("b"),
      success = "false")
  )),
  file.path(pipe, "build_log_20260101_000000_aaa.json"),
  auto_unbox = TRUE
)
jsonlite::write_json(
  list(nodes = list()),
  file.path(pipe, "build_log_20260102_000000_zzz.json"),
  auto_unbox = TRUE
)

logs <- list_logs(pipeline_dir = pipe)
stopifnot(identical(logs$filename,
  c("build_log_20260102_000000_zzz.json", "build_log_20260101_000000_aaa.json")))
stopifnot(is.na(logs$pipeline[[1L]]) && identical(logs$pipeline[[2L]], "demo"))
stopifnot(grepl("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$", logs$modification_time[[1L]]))
cat("list_logs ok\n")

tbl <- build_log_to_frame(which_log = "20260101", pipeline_dir = pipe)
stopifnot(identical(tbl$name, c("a", "b", "c")))
stopifnot(identical(tbl$status[[1L]], "Completed"))
stopifnot(identical(tbl$duration[[1L]], 1.5))
stopifnot(identical(tbl$duration[[2L]], 2))
stopifnot(is.na(tbl$duration[[3L]]))
stopifnot(identical(tbl$status[[3L]], "SoftFailed"))
cat("build_log_to_frame ok\n")

# Exceptions with warnings sidecar.
art_dir <- file.path(td, "art")
dir.create(art_dir)
artifact <- file.path(art_dir, "artifact")
writeBin(charToRaw("x"), artifact)
jsonlite::write_json(
  list("late column", list(kind = "NA", message = "3 NAs")),
  file.path(art_dir, "warnings"),
  auto_unbox = TRUE
)
jsonlite::write_json(
  list(nodes = list(
    list(node = "bad", path = "/tmp/nonexistent", runtime = "T", class = "Error",
      status = "Errored", error_code = "NixError", error_message = "line1\nboom"),
    list(node = "soft", path = artifact, runtime = "T", class = "VError",
      status = "SoftFailed", error_code = "ValueError", error_message = "bad value"),
    list(node = "warned", path = artifact, runtime = "T", class = "DataFrame",
      status = "Completed", warnings = TRUE),
    list(node = "ok", path = artifact, runtime = "T", class = "DataFrame",
      status = "Completed")
  )),
  file.path(pipe, "build_log_20260103_000000_qqq.json"),
  auto_unbox = TRUE
)
errs <- collect_exceptions(which_log = "20260103", pipeline_dir = pipe)
stopifnot(identical(sort(unique(errs$node)), c("bad", "soft", "warned")))
bad <- errs[errs$node == "bad", ]
stopifnot(identical(bad$status, "Error") && identical(bad$code, "NixError") && identical(bad$message, "boom"))
warns <- errs[errs$status == "Warning", ]
stopifnot(nrow(warns) == 2L && identical(warns$code[[2L]], "NA"))
cat("collect_exceptions ok\n")

cat("ALL FRAME TESTS PASSED\n")

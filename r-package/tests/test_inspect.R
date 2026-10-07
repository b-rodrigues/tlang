# Tests for inspect_node(), lineage(), error_msg(), warning_msg().
# Runs under `R CMD check` (via `library(tlang)`) and via
# `Rscript r-package/tests/test_inspect.R` from the repository root
# inside `nix develop`.

library(tlang)

td <- tempfile()
dir.create(td, recursive = TRUE)
pipe <- file.path(td, "_pipeline")
dir.create(pipe)

art <- file.path(td, "a.txt")
writeBin(charToRaw("a"), art)

mk_entry <- function(node, path, ...) {
  entry <- list(node = node, path = path, runtime = "R",
    serializer = "default", dependencies = list(),
    status = "Completed", class = "DataFrame")
  dots <- list(...)
  for (nm in names(dots)) {
    entry[[nm]] <- dots[[nm]]
  }
  entry
}

jsonlite::write_json(
  list(nodes = list(
    mk_entry("a", art),
    mk_entry("b", art, dependencies = list("a"), serializer = "json")
  )),
  file.path(pipe, "build_log_20260101_000000_abc.json"),
  auto_unbox = TRUE
)

info <- inspect_node("b", pipeline_dir = pipe)
stopifnot(identical(info$name, "b"))
stopifnot(identical(info$runtime, "R"))
stopifnot(identical(info$serializer, "json"))
stopifnot(identical(info$dependencies, "a"))
stopifnot(identical(info$children, character(0)))
stopifnot(identical(info$status, "Completed"))
stopifnot(is.null(info$error))
root <- inspect_node("a", pipeline_dir = pipe)
stopifnot(identical(root$children, "b"))
cat("inspect_node ok\n")

jsonlite::write_json(
  list(nodes = list(
    mk_entry("a", art),
    mk_entry("b", art, dependencies = list("a")),
    mk_entry("c", art, dependencies = list("b"))
  )),
  file.path(pipe, "build_log_20260102_000000_def.json"),
  auto_unbox = TRUE
)
sel <- "20260102"
lin <- lineage("b", pipeline_dir = pipe, which_log = sel)
stopifnot(identical(lin$parents, "a") && identical(lin$children, "c"))
lin <- lineage("c", pipeline_dir = pipe, which_log = sel, direction = "parents")
stopifnot(identical(lin$parents, c("b", "a")) && identical(lin$children, character(0)))
err <- tryCatch(
  lineage("a", pipeline_dir = pipe, direction = "sideways"),
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("should be one of", err))
cat("lineage ok\n")

# An R failure reads the same from R: plain VError JSON.
verror <- file.path(td, "err.json")
jsonlite::write_json(
  list(type = "VError", code = "RunError",
    message = "Error in lm.fit(x, y) : NA/NaN/Inf in 'y'",
    na_count = 0, context = list(runtime = "R")),
  verror,
  auto_unbox = TRUE
)
ok_art <- file.path(td, "ok.txt")
writeBin(charToRaw("ok"), ok_art)
jsonlite::write_json(
  list(nodes = list(
    mk_entry("bad", verror, status = "SoftFailed", class = "VError"),
    mk_entry("good", ok_art)
  )),
  file.path(pipe, "build_log_20260103_000000_ghi.json"),
  auto_unbox = TRUE
)
err_msg <- error_msg("bad", pipeline_dir = pipe, which_log = "20260103")
stopifnot(grepl("lm.fit", err_msg, fixed = TRUE))
stopifnot(identical(error_code("bad", pipeline_dir = pipe, which_log = "20260103"), "RunError"))
stopifnot(identical(error_context("bad", pipeline_dir = pipe, which_log = "20260103")$runtime, "R"))
err <- tryCatch(
  error_msg("good", pipeline_dir = pipe, which_log = "20260103"),
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("no error", err))
info <- inspect_node("bad", pipeline_dir = pipe, which_log = "20260103")
stopifnot(grepl("lm.fit", info$error$message, fixed = TRUE))
stopifnot(identical(warning_msg("good", pipeline_dir = pipe, which_log = "20260103"), ""))
cat("error_msg ok\n")

# warning_msg joins own and upstream warnings like T.
parent_dir <- file.path(td, "parent_art")
dir.create(parent_dir)
writeBin(charToRaw("x"), file.path(parent_dir, "artifact"))
jsonlite::write_json(list("stale column"), file.path(parent_dir, "warnings"), auto_unbox = TRUE)
child_dir <- file.path(td, "child_art")
dir.create(child_dir)
writeBin(charToRaw("x"), file.path(child_dir, "artifact"))
jsonlite::write_json(list("late column"), file.path(child_dir, "warnings"), auto_unbox = TRUE)
jsonlite::write_json(
  list(nodes = list(
    mk_entry("parent", file.path(parent_dir, "artifact"), warnings = TRUE),
    mk_entry("child", file.path(child_dir, "artifact"),
      dependencies = list("parent"), warnings = TRUE)
  )),
  file.path(pipe, "build_log_20260104_000000_jkl.json"),
  auto_unbox = TRUE
)
stopifnot(identical(
  warning_msg("child", pipeline_dir = pipe, which_log = "20260104"),
  "late column. Furthermore, Ancestor node 'parent' reported following warning: stale column"
))
stopifnot(identical(
  warning_msg("parent", pipeline_dir = pipe, which_log = "20260104"),
  "stale column"
))
cat("warning_msg ok\n")

# Completed status with a VError class still counts as failed.
verror2 <- file.path(td, "err2.json")
jsonlite::write_json(
  list(type = "VError", code = "RunError", message = "boom", na_count = 0),
  verror2,
  auto_unbox = TRUE
)
jsonlite::write_json(
  list(nodes = list(
    mk_entry("a", verror2, status = "Completed", class = "VError")
  )),
  file.path(pipe, "build_log_20260105_000000_cmp.json"),
  auto_unbox = TRUE
)
stopifnot(identical(error_code("a", pipeline_dir = pipe, which_log = "cmp"), "RunError"))
errs <- collect_exceptions(pipe, "20260105")
stopifnot(nrow(errs) == 1L && identical(errs$code, "RunError"))
cat("completed-verror ok\n")

# SoftFailed with a plain class still reads a VError artifact.
jsonlite::write_json(
  list(nodes = list(
    mk_entry("a", verror2, status = "SoftFailed", class = "DataFrame")
  )),
  file.path(pipe, "build_log_20260105_000000_sf.json"),
  auto_unbox = TRUE
)
stopifnot(identical(error_code("a", pipeline_dir = pipe, which_log = "000000_sf"), "RunError"))
cat("softfailed-class ok\n")

# A healthy node never opens its artifact, even when the file holds
# valid VError JSON.
jsonlite::write_json(
  list(nodes = list(mk_entry("a", verror2))),
  file.path(pipe, "build_log_20260105_000000_ok.json"),
  auto_unbox = TRUE
)
err <- tryCatch(
  error_msg("a", pipeline_dir = pipe, which_log = "000000_ok"),
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("no error", err))
info <- inspect_node("a", pipeline_dir = pipe, which_log = "000000_ok")
stopifnot(is.null(info$error))
cat("healthy-verror ok\n")

# Message without a code keeps the class as the code.
a_txt <- file.path(td, "a.txt")
writeBin(charToRaw("x"), a_txt)
jsonlite::write_json(
  list(nodes = list(
    list(node = "a", path = a_txt, runtime = "T", serializer = "text",
      dependencies = list(), status = "SoftFailed", class = "VError",
      error_message = "just a message")
  )),
  file.path(pipe, "build_log_20260106_000000_cls.json"),
  auto_unbox = TRUE
)
errs <- collect_exceptions(pipe, "20260106")
stopifnot(identical(errs$code, "VError"))
cat("class fallback ok\n")

# A healthy node with a dangling artifact path never opens the file.
jsonlite::write_json(
  list(nodes = list(
    mk_entry("a", "/tmp/definitely-missing-artifact")
  )),
  file.path(pipe, "build_log_20260107_000000_dng.json"),
  auto_unbox = TRUE
)
err <- tryCatch(
  error_msg("a", pipeline_dir = pipe, which_log = "dng"),
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("no error", err))
info <- inspect_node("a", pipeline_dir = pipe, which_log = "dng")
stopifnot(is.null(info$error))
cat("dangling path ok\n")

# Neighbor order is sorted within each level in every language.
jsonlite::write_json(
  list(nodes = list(
    mk_entry("a", a_txt),
    mk_entry("z", a_txt, dependencies = list("a")),
    mk_entry("m", a_txt, dependencies = list("a")),
    mk_entry("leaf", a_txt, dependencies = list("z", "m"))
  )),
  file.path(pipe, "build_log_20260108_000000_dia.json"),
  auto_unbox = TRUE
)
lin <- lineage("leaf", pipeline_dir = pipe, which_log = "dia", direction = "parents")
stopifnot(identical(lin$parents, c("m", "z", "a")))
lin <- lineage("a", pipeline_dir = pipe, which_log = "dia", direction = "children")
stopifnot(identical(lin$children, c("m", "z", "leaf")))
cat("lineage order ok\n")

# Byte order (not locale order) in every language: B < _ < a < a1.
jsonlite::write_json(
  list(nodes = list(
    mk_entry("root", a_txt),
    mk_entry("a1", a_txt, dependencies = list("root")),
    mk_entry("a", a_txt, dependencies = list("root")),
    mk_entry("_x", a_txt, dependencies = list("root")),
    mk_entry("B", a_txt, dependencies = list("root"))
  )),
  file.path(pipe, "build_log_20260109_000000_byte.json"),
  auto_unbox = TRUE
)
lin <- lineage("root", pipeline_dir = pipe, which_log = "byte", direction = "children")
stopifnot(identical(lin$children, c("B", "_x", "a", "a1")))
cat("byte order ok\n")

cat("ALL INSPECT TESTS PASSED\n")

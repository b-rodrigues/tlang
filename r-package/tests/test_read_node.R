# Tests for read_node() auto-dispatch and read_node_tree().
# Runs under `R CMD check` (via `library(tlang)`) and via
# `Rscript r-package/tests/test_read_node.R` from the repository root
# inside `nix develop`.

library(tlang)

normalize_serializer <- tlang:::normalize_serializer
read_build_log <- tlang:::read_build_log
build_log_deps_map <- tlang:::build_log_deps_map

stopifnot(identical(normalize_serializer("^JSON"), "json"))
stopifnot(identical(normalize_serializer("  ^Csv "), "csv"))
stopifnot(identical(normalize_serializer(NULL), "default"))
stopifnot(identical(normalize_serializer(""), "default"))
cat("normalize ok\n")

make_log <- function(pipe, nodes, name = "build_log_20260101_000000_abc.json") {
  dir.create(pipe, showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(
    list(nodes = nodes),
    file.path(pipe, name),
    auto_unbox = TRUE
  )
}

mk_node <- function(name, path, serializer, deps) {
  list(
    node = name,
    path = path,
    serializer = serializer,
    dependencies = as.list(deps),
    runtime = "T",
    class = "String",
    status = "Completed"
  )
}

td <- tempfile()
dir.create(td, recursive = TRUE)
pipe <- file.path(td, "_pipeline")

# Auto dispatch: json, csv, text (CRLF preserved), default.
json_path <- file.path(td, "v.json")
jsonlite::write_json(list(a = 1), json_path, auto_unbox = TRUE)
csv_path <- file.path(td, "t.csv")
write.csv(data.frame(x = c(1, 2), y = c(3, 4)), csv_path, row.names = FALSE)
text_path <- file.path(td, "t.txt")
writeBin(charToRaw("hello\r\n"), text_path)
utf8_path <- file.path(td, "u.txt")
writeBin(charToRaw("h\xc3\xa9llo\r\n"), utf8_path)
rds_path <- file.path(td, "m.rds")
saveRDS(list(w = 1), rds_path)
make_log(pipe, list(
  mk_node("j", json_path, "json", c()),
  mk_node("c", csv_path, "^csv", c()),
  mk_node("t", text_path, "text", c()),
  mk_node("u", utf8_path, "text", c()),
  mk_node("m", rds_path, "default", c())
))
stopifnot(identical(read_node("j", pipeline_dir = pipe)$a, 1L))
frame <- read_node("c", pipeline_dir = pipe)
stopifnot(all(c("x", "y") %in% names(frame)))
got_text <- read_node("t", pipeline_dir = pipe)
stopifnot(identical(got_text, "hello\r\n"))
got_utf8 <- read_node("u", pipeline_dir = pipe)
stopifnot(identical(got_utf8, "h\u00e9llo\r\n"))
stopifnot(identical(Encoding(got_utf8), "UTF-8"))
stopifnot(identical(read_node("m", pipeline_dir = pipe)$w, 1))
cat("auto dispatch ok\n")

# IPC and Parquet round-trips (arrow is in Suggests).
if (requireNamespace("arrow", quietly = TRUE)) {
  ipc_path <- file.path(td, "t.ipc")
  arrow::write_ipc_file(data.frame(x = c(1, 2)), ipc_path)
  pq_path <- file.path(td, "t.parquet")
  arrow::write_parquet(data.frame(x = c(1, 2)), pq_path)
  make_log(pipe, list(
    mk_node("i", ipc_path, "^ipc", c()),
    mk_node("p", pq_path, "^parquet", c())
  ), name = "build_log_20260101_000000_ipc.json")
  stopifnot(identical(read_node("i", pipeline_dir = pipe, which_log = "ipc")$x, c(1, 2)))
  stopifnot(identical(read_node("p", pipeline_dir = pipe, which_log = "ipc")$x, c(1, 2)))
  cat("ipc/parquet ok\n")
}

# Runtime mismatch hint: a Python pickle is not an RDS file.
pkl_path <- file.path(td, "m.pkl")
writeBin(charToRaw("not an rds file"), pkl_path)
make_log(pipe, list(
  list(node = "m", path = pkl_path, serializer = "default",
    dependencies = list(), runtime = "Python", class = "DataFrame",
    status = "Completed")
), name = "build_log_20260101_000000_rt.json")
err <- tryCatch(
  read_node("m", pipeline_dir = pipe, which_log = "000000_rt"),
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("built by runtime `Python`", err, fixed = TRUE))
cat("runtime hint ok\n")

# Unknown and pmml errors mention return_path.
weird_path <- file.path(td, "w.bin")
writeBin(charToRaw("x"), weird_path)
make_log(pipe, list(mk_node("w", weird_path, "weirdfmt", c())),
  name = "build_log_20260102_000000_def.json")
err <- tryCatch(
  read_node("w", pipeline_dir = pipe, which_log = "20260102"),
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("weirdfmt", err) && grepl("return_path", err))

pmml_path <- file.path(td, "m.pmml")
writeBin(charToRaw("<PMML/>"), pmml_path)
make_log(pipe, list(mk_node("p", pmml_path, "pmml", c())),
  name = "build_log_20260103_000000_ghi.json")
err <- tryCatch(
  read_node("p", pipeline_dir = pipe, which_log = "20260103"),
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("return_path", err))
cat("error messages ok\n")

# Tree: children, parents, both, cycles, missing deps, NULL preservation.
a_path <- file.path(td, "a.txt")
b_path <- file.path(td, "b.txt")
c_path <- file.path(td, "c.txt")
writeBin(charToRaw("a"), a_path)
writeBin(charToRaw("b"), b_path)
writeBin(charToRaw("c"), c_path)
make_log(pipe, list(
  mk_node("a", a_path, "text", c()),
  mk_node("b", b_path, "text", c("a")),
  mk_node("c", c_path, "text", c("b"))
), name = "build_log_20260104_000000_jkl.json")
sel <- "20260104"
stopifnot(identical(
  sort(names(read_node_tree("a", pipeline_dir = pipe, which_log = sel))),
  c("a", "b", "c")
))
stopifnot(identical(
  sort(names(read_node_tree("c", pipeline_dir = pipe, which_log = sel, include = "parents"))),
  c("a", "b", "c")
))
both <- read_node_tree("b", pipeline_dir = pipe, which_log = sel, include = "both")
stopifnot(identical(sort(names(both)), c("a", "b", "c")) && identical(both[["b"]], "b"))
cat("tree closure ok\n")

# build_log$nodes parses as a list of entries (not a data frame).
log <- read_build_log(file.path(pipe, "build_log_20260104_000000_jkl.json"))
stopifnot(is.list(log$nodes) && is.list(log$nodes[[1L]]))
deps <- build_log_deps_map(log$nodes)
stopifnot(identical(deps[["b"]], "a"))
cat("build log shape ok\n")

# Cycle terminates.
make_log(pipe, list(
  mk_node("a", a_path, "text", c("b")),
  mk_node("b", b_path, "text", c("a"))
), name = "build_log_20260105_000000_mno.json")
tree <- read_node_tree("a", pipeline_dir = pipe, which_log = "20260105", include = "both")
stopifnot(identical(sort(names(tree)), c("a", "b")))
cat("cycle ok\n")

# Missing dependency errors naming the ghost.
make_log(pipe, list(mk_node("a", a_path, "text", c("ghost"))),
  name = "build_log_20260106_000000_pqr.json")
err <- tryCatch(
  read_node_tree("a", pipeline_dir = pipe, which_log = "20260106", include = "parents"),
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("ghost", err))
cat("missing dep ok\n")

# NULL values are kept, not dropped.
n_path <- file.path(td, "n.rds")
saveRDS(NULL, n_path)
make_log(pipe, list(
  mk_node("n", n_path, "default", c()),
  mk_node("t", a_path, "text", c("n"))
), name = "build_log_20260107_000000_stu.json")
tree <- read_node_tree("n", pipeline_dir = pipe, which_log = "20260107")
stopifnot(all(c("n", "t") %in% names(tree)) && is.null(tree[["n"]]))
cat("NULL preserved ok\n")

# Snapshot race: omit which_log so "latest" is used. The racing deserializer
# writes a newer log that rewrites b to different contents; the in-progress
# tree must still return the original contents.
td_race <- tempfile()
dir.create(td_race, recursive = TRUE)
pipe_race <- file.path(td_race, "_pipeline")
a_race <- file.path(td_race, "a.txt")
b_orig <- file.path(td_race, "b.txt")
b_new <- file.path(td_race, "b_new.txt")
writeBin(charToRaw("one"), a_race)
writeBin(charToRaw("two"), b_orig)
writeBin(charToRaw("CHANGED"), b_new)
make_log(pipe_race, list(
  mk_node("a", a_race, "text", c()),
  mk_node("b", b_orig, "text", c("a"))
), name = "build_log_20260101_000000_aaa.json")
racing <- function(path) {
  jsonlite::write_json(
    list(nodes = list(
      mk_node("a", a_race, "text", c()),
      mk_node("b", b_new, "text", c("a")),
      mk_node("c", c_path, "text", c("b"))
    )),
    file.path(pipe_race, "build_log_20260102_000000_zzz.json"),
    auto_unbox = TRUE
  )
  out <- readChar(path, file.info(path)$size, useBytes = TRUE)
  Encoding(out) <- "UTF-8"
  out
}
tree <- read_node_tree("a",
  pipeline_dir = pipe_race,
  deserializer = racing, include = "children")
stopifnot(identical(sort(names(tree)), c("a", "b")))
stopifnot(identical(tree[["b"]], "two"))
cat("snapshot race ok\n")

# Unreadable node handling warns and falls back.
make_log(pipe, list(
  mk_node("good", a_path, "text", c()),
  mk_node("bad", pmml_path, "pmml", c("good"))
), name = "build_log_20260110_000000_yza.json")
sel10 <- "20260110"
err <- tryCatch(
  read_node_tree("good", pipeline_dir = pipe, which_log = sel10),
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("pmml", err, ignore.case = TRUE))
warned <- NULL
as_path <- withCallingHandlers(
  read_node_tree("good",
    pipeline_dir = pipe, which_log = sel10, on_unreadable = "path"),
  warning = function(w) {
    warned <<- c(warned, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)
stopifnot(any(grepl("bad", warned)))
stopifnot(identical(as_path[["good"]], "a") && grepl("m.pmml$", as_path[["bad"]]))
warned <- NULL
skipped <- withCallingHandlers(
  read_node_tree("good",
    pipeline_dir = pipe, which_log = sel10, on_unreadable = "skip"),
  warning = function(w) {
    warned <<- c(warned, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)
stopifnot(any(grepl("bad", warned)))
stopifnot(identical(names(skipped), "good"))
cat("on_unreadable ok\n")

cat("ALL R TESTS PASSED\n")

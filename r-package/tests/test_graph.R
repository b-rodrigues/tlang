library(tlang)

pipe <- file.path(tempdir(), "_pipeline_graph")
dir.create(pipe, showWarnings = FALSE, recursive = TRUE)
dag <- list(
  list(node_name = "a", depends = list()),
  list(node_name = "b", depends = list("a")),
  list(node_name = "c", depends = list("a", "b"))
)
jsonlite::write_json(dag, file.path(pipe, "dag.json"), auto_unbox = TRUE)

edges <- pipeline_edges(pipe)
stopifnot(nrow(edges) == 3L)
stopifnot(identical(edges$from, c("a", "a", "b")))
stopifnot(identical(edges$to, c("b", "c", "c")))
stopifnot(identical(pipeline_roots(pipe), "a"))
stopifnot(identical(pipeline_leaves(pipe), "c"))
stopifnot(pipeline_depth(pipe) == 2L)
stopifnot(length(pipeline_cycles(pipe)) == 0L)
stopifnot(length(pipeline_validate(pipe)) == 0L)
stopifnot(grepl("digraph pipeline", pipeline_to_dot(pipe), fixed = TRUE))
stopifnot(grepl("graph LR", pipeline_to_mermaid(pipe), fixed = TRUE))
cat("graph helpers ok\n")

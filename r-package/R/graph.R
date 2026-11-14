#' Load node -> dependencies map from build log or DAG file
#'
#' Uses the latest build log when logs exist, else the static DAG file.
#'
#' @param pipeline_dir Path to the pipeline directory.
#' @param which_log Optional log regex.
#' @param dag_file DAG filename used only when no build logs exist.
#' @return Named list of character vectors.
#' @keywords internal
load_deps_map <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json") {
  validate_scalar_string(pipeline_dir, "pipeline_dir")
  validate_scalar_string(dag_file, "dag_file")
  if (!dir.exists(pipeline_dir)) {
    stop(sprintf("Pipeline directory `%s` does not exist.", pipeline_dir), call. = FALSE)
  }
  logs <- list_build_logs(pipeline_dir)
  if (length(logs) > 0L) {
    log_file <- select_build_log(logs, which_log, pipeline_dir)
    build_log <- read_build_log(file.path(pipeline_dir, log_file))
    nodes <- build_log$nodes
    if (!is.list(nodes)) {
      stop(sprintf("Build log `%s` does not contain a `nodes` array.", log_file), call. = FALSE)
    }
    out <- list()
    for (entry in nodes) {
      if (!is.list(entry) || is.null(entry$node)) next
      nm <- as.character(entry$node)[[1L]]
      if (is.na(nm) || !nzchar(nm)) next
      deps <- entry$dependencies
      if (is.null(deps)) deps <- character(0)
      else if (is.list(deps)) deps <- unlist(deps)
      deps <- sort(unique(as.character(deps[!is.na(deps) & nzchar(deps)])))
      out[[nm]] <- deps
    }
    return(out)
  }
  dag_path <- file.path(pipeline_dir, dag_file)
  if (!file.exists(dag_path)) {
    stop(sprintf("DAG file `%s` does not exist.", dag_path), call. = FALSE)
  }
  dag <- tryCatch(
    jsonlite::fromJSON(dag_path, simplifyVector = FALSE),
    error = function(err) {
      stop(sprintf("Failed to read DAG file `%s`: %s", dag_path, conditionMessage(err)), call. = FALSE)
    }
  )
  if (!is.list(dag)) {
    stop(sprintf("DAG file `%s` must decode to an array.", dag_path), call. = FALSE)
  }
  out <- list()
  for (i in seq_along(dag)) {
    entry <- validate_node_entry(dag[[i]], i, dag_path)
    out[[entry$node_name]] <- entry$depends
  }
  out
}

#' Pipeline dependency edges
#'
#' Mirrors T `pipeline_edges`. Returns one row per edge.
#' @param pipeline_dir Path to pipeline dir.
#' @param which_log Optional log regex.
#' @param dag_file DAG filename when no logs exist.
#' @return Data frame with columns `from` and `to`.
#' @export
pipeline_edges <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json") {
  deps_map <- load_deps_map(pipeline_dir, which_log, dag_file)
  from <- character(0)
  to <- character(0)
  for (nm in names(deps_map)) {
    for (dep in deps_map[[nm]]) {
      from <- c(from, dep)
      to <- c(to, nm)
    }
  }
  data.frame(from = from, to = to, stringsAsFactors = FALSE)
}

#' Pipeline root nodes
#'
#' Mirrors T `pipeline_roots`: nodes with no dependencies.
#' @param pipeline_dir Path to pipeline dir.
#' @param which_log Optional log regex.
#' @param dag_file DAG filename when no logs exist.
#' @return Character vector of root names.
#' @export
pipeline_roots <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json") {
  deps_map <- load_deps_map(pipeline_dir, which_log, dag_file)
  names(deps_map)[vapply(deps_map, function(d) length(d) == 0L, logical(1))]
}

#' Pipeline leaf nodes
#'
#' Mirrors T `pipeline_leaves`: nodes no other node depends on.
#' @param pipeline_dir Path to pipeline dir.
#' @param which_log Optional log regex.
#' @param dag_file DAG filename when no logs exist.
#' @return Character vector of leaf names.
#' @export
pipeline_leaves <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json") {
  deps_map <- load_deps_map(pipeline_dir, which_log, dag_file)
  all_deps <- unique(unlist(deps_map, use.names = FALSE))
  names(deps_map)[!names(deps_map) %in% all_deps]
}

#' Topological depth per node
#'
#' Roots have depth 0. Cycles resolve to 0 on the back edge.
#' @param pipeline_dir Path to pipeline dir.
#' @param which_log Optional log regex.
#' @param dag_file DAG filename when no logs exist.
#' @return Named integer vector.
#' @export
pipeline_node_depths <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json") {
  deps_map <- load_deps_map(pipeline_dir, which_log, dag_file)
  cache <- new.env(parent = emptyenv())
  depth_of <- function(name, seen = character(0)) {
    if (exists(name, envir = cache, inherits = FALSE)) return(get(name, envir = cache))
    if (name %in% seen) return(0L)
    deps <- deps_map[[name]]
    if (is.null(deps) || length(deps) == 0L) {
      assign(name, 0L, envir = cache)
      return(0L)
    }
    d <- 1L + max(vapply(deps, function(dep) depth_of(dep, c(seen, name)), integer(1)))
    assign(name, d, envir = cache)
    d
  }
  out <- vapply(names(deps_map), depth_of, integer(1))
  names(out) <- names(deps_map)
  out
}

#' Maximum topological depth
#'
#' Mirrors T `pipeline_depth`.
#' @param pipeline_dir Path to pipeline dir.
#' @param which_log Optional log regex.
#' @param dag_file DAG filename when no logs exist.
#' @return Integer maximum depth.
#' @export
pipeline_depth <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json") {
  depths <- pipeline_node_depths(pipeline_dir, which_log, dag_file)
  if (length(depths) == 0L) return(0L)
  max(depths)
}

#' Detect pipeline cycles
#'
#' Mirrors T `pipeline_cycles`. Empty means the DAG is valid.
#' @param pipeline_dir Path to pipeline dir.
#' @param which_log Optional log regex.
#' @param dag_file DAG filename when no logs exist.
#' @return Character vector of nodes in cycles.
#' @export
pipeline_cycles <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json") {
  deps_map <- load_deps_map(pipeline_dir, which_log, dag_file)
  color <- setNames(rep(0L, length(deps_map)), names(deps_map))
  cycle_nodes <- character(0)
  visit <- function(name) {
    c <- color[[name]]
    if (c == 1L) {
      if (!name %in% cycle_nodes) cycle_nodes <<- c(cycle_nodes, name)
      return()
    }
    if (c != 0L) return()
    color[[name]] <<- 1L
    for (dep in deps_map[[name]]) {
      if (dep %in% names(deps_map)) visit(dep)
    }
    color[[name]] <<- 2L
  }
  for (nm in names(deps_map)) visit(nm)
  cycle_nodes
}

#' Validate pipeline structure
#'
#' Structural subset of T `pipeline_validate`: unknown deps plus cycles.
#' @param pipeline_dir Path to pipeline dir.
#' @param which_log Optional log regex.
#' @param dag_file DAG filename when no logs exist.
#' @return Character vector of error messages (empty = valid).
#' @export
pipeline_validate <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json") {
  deps_map <- load_deps_map(pipeline_dir, which_log, dag_file)
  errors <- character(0)
  for (nm in names(deps_map)) {
    for (dep in deps_map[[nm]]) {
      if (!dep %in% names(deps_map)) {
        errors <- c(errors, sprintf("Node `%s` depends on `%s` which does not exist in the pipeline.", nm, dep))
      }
    }
  }
  cycles <- pipeline_cycles(pipeline_dir, which_log, dag_file)
  if (length(cycles) > 0L) {
    errors <- c(errors, sprintf("Pipeline has dependency cycle(s) involving: %s.", paste(cycles, collapse = ", ")))
  }
  errors
}

#' Export pipeline graph as DOT
#'
#' @param pipeline_dir Path to pipeline dir.
#' @param which_log Optional log regex.
#' @param dag_file DAG filename when no logs exist.
#' @param title Optional graph title.
#' @return Character scalar DOT string.
#' @export
pipeline_to_dot <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json", title = NULL) {
  deps_map <- load_deps_map(pipeline_dir, which_log, dag_file)
  lines <- c("digraph pipeline {")
  if (!is.null(title)) {
    lines <- c(lines, sprintf('  label="%s";', gsub('"', '\\"', title, fixed = TRUE)))
  }
  lines <- c(lines, "  rankdir=LR;", "  node [shape=box];")
  for (nm in names(deps_map)) lines <- c(lines, sprintf('  "%s";', nm))
  for (nm in names(deps_map)) {
    for (dep in deps_map[[nm]]) {
      lines <- c(lines, sprintf('  "%s" -> "%s";', dep, nm))
    }
  }
  paste(c(lines, "}"), collapse = "\n")
}

#' Export pipeline graph as Mermaid
#'
#' @param pipeline_dir Path to pipeline dir.
#' @param which_log Optional log regex.
#' @param dag_file DAG filename when no logs exist.
#' @param title Optional graph title.
#' @return Character scalar Mermaid string.
#' @export
pipeline_to_mermaid <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json", title = NULL) {
  deps_map <- load_deps_map(pipeline_dir, which_log, dag_file)
  ids <- setNames(sprintf("n%d", seq_along(deps_map)), names(deps_map))
  lines <- character(0)
  if (!is.null(title)) lines <- c(lines, "---", sprintf("tlang-title: %s", title), "---")
  lines <- c(lines, "graph LR")
  for (nm in names(deps_map)) lines <- c(lines, sprintf('  %s["%s"];', ids[[nm]], nm))
  for (nm in names(deps_map)) {
    for (dep in deps_map[[nm]]) {
      if (dep %in% names(ids)) lines <- c(lines, sprintf("  %s --> %s;", ids[[dep]], ids[[nm]]))
    }
  }
  paste(lines, collapse = "\n")
}

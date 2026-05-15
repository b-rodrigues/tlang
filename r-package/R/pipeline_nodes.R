validate_node_entry <- function(entry, index, dag_file) {
  if (!is.list(entry)) {
    stop(
      sprintf("Entry %d in `%s` must be an object.", index, dag_file),
      call. = FALSE
    )
  }

  node_name <- entry$node_name
  depends <- entry$depends

  if (!is.character(node_name) || length(node_name) != 1L || is.na(node_name) || !nzchar(node_name)) {
    stop(
      sprintf("Entry %d in `%s` has an invalid `node_name`.", index, dag_file),
      call. = FALSE
    )
  }

  if (is.null(depends)) {
    depends <- character(0)
  }

  if (!is.character(depends) || any(is.na(depends)) || any(!nzchar(depends))) {
    stop(
      sprintf("Node `%s` in `%s` has an invalid `depends` list.", node_name, dag_file),
      call. = FALSE
    )
  }

  list(node_name = node_name, depends = unique(depends))
}

render_node_tree <- function(node, children_map, prefix = "", is_last = TRUE, seen = character(0), depth = 0L) {
  connector <- if (depth == 0L) "" else if (is_last) "└─ " else "├─ "
  line <- paste0(prefix, connector, node)

  if (node %in% seen) {
    return(c(line, paste0(prefix, if (is_last) "   " else "│  ", "↺ cycle detected")))
  }

  children <- children_map[[node]]
  if (is.null(children) || length(children) == 0L) {
    return(line)
  }

  next_prefix <- paste0(prefix, if (is_last) "   " else "│  ")
  rendered_children <- unlist(
    lapply(seq_along(children), function(i) {
      render_node_tree(children[[i]], children_map, next_prefix, i == length(children), c(seen, node), depth + 1L)
    }),
    use.names = FALSE
  )

  c(line, rendered_children)
}

#' List pipeline nodes from `_pipeline/dag.json` in a tree-like view
#'
#' Reads a pipeline DAG definition from `_pipeline/dag.json` and returns a
#' character vector representing the pipeline structure as an ASCII tree.
#'
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#' @param dag_file Name of the DAG JSON file inside `pipeline_dir`.
#'   Defaults to `"dag.json"`.
#'
#' @return Character vector with one line per rendered tree node.
#' @export
pipeline_nodes <- function(pipeline_dir = "_pipeline", dag_file = "dag.json") {
  validate_scalar_string(pipeline_dir, "pipeline_dir")
  validate_scalar_string(dag_file, "dag_file")

  if (!dir.exists(pipeline_dir)) {
    stop(sprintf("Pipeline directory `%s` does not exist.", pipeline_dir), call. = FALSE)
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

  normalized <- lapply(seq_along(dag), function(i) validate_node_entry(dag[[i]], i, dag_path))
  node_names <- vapply(normalized, `[[`, character(1), "node_name")

  if (any(duplicated(node_names))) {
    duplicated_names <- unique(node_names[duplicated(node_names)])
    stop(sprintf("DAG file `%s` has duplicate node_name values: %s", dag_path, paste(duplicated_names, collapse = ", ")), call. = FALSE)
  }

  unknown_dependencies <- unique(unlist(lapply(normalized, function(entry) setdiff(entry$depends, node_names)), use.names = FALSE))
  if (length(unknown_dependencies) > 0L) {
    stop(sprintf("DAG file `%s` references unknown dependencies: %s", dag_path, paste(unknown_dependencies, collapse = ", ")), call. = FALSE)
  }

  children_map <- stats::setNames(vector("list", length(node_names)), node_names)
  incoming_count <- stats::setNames(integer(length(node_names)), node_names)

  for (entry in normalized) {
    for (parent in entry$depends) {
      children_map[[parent]] <- c(children_map[[parent]], entry$node_name)
      incoming_count[[entry$node_name]] <- incoming_count[[entry$node_name]] + 1L
    }
  }

  children_map <- lapply(children_map, sort)
  roots <- sort(names(incoming_count[incoming_count == 0L]))
  if (length(roots) == 0L) {
    roots <- sort(node_names)
  }

  lines <- unlist(
    lapply(seq_along(roots), function(i) {
      render_node_tree(roots[[i]], children_map, prefix = "", is_last = i == length(roots))
    }),
    use.names = FALSE
  )

  lines
}

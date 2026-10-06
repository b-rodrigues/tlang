#' Extract a dependency map from a build log nodes array
#'
#' @param nodes List of node entries from the build log.
#'
#' @return Named list mapping node name to character vector of dependencies.
#'
#' @keywords internal
build_log_deps_map <- function(nodes) {
  deps_map <- list()
  if (!is.list(nodes)) {
    return(deps_map)
  }
  for (entry in nodes) {
    if (!is.list(entry) || is.null(entry$node)) {
      next
    }
    nm <- as.character(entry$node)[[1L]]
    deps <- entry$dependencies
    if (is.null(deps)) {
      deps <- character(0)
    } else if (is.list(deps)) {
      deps <- unlist(deps)
    }
    deps <- as.character(deps)
    deps <- deps[!is.na(deps) & nzchar(deps)]
    deps_map[[nm]] <- unique(sort(deps))
  }
  deps_map
}

#' Compute the transitive closure over dependencies or dependents
#'
#' @param deps_map Named list of node -> direct dependencies.
#' @param name Character. Root node name.
#' @param include Character. One of `"children"`, `"parents"`, `"both"`.
#'
#' @return Character vector of node names including the root first.
#'
#' @keywords internal
closure_nodes <- function(deps_map, name, include) {
  include <- match.arg(include, c("children", "parents", "both"))
  if (!(name %in% names(deps_map))) {
    stop(sprintf("Node `%s` not found in build log.", name), call. = FALSE)
  }

  # Precomputed reverse map: dependency -> direct dependents.
  children_map <- list()
  for (node in names(deps_map)) {
    for (dep in deps_map[[node]]) {
      children_map[[dep]] <- c(children_map[[dep]], node)
    }
  }

  seen <- c(name)
  queue <- c(name)
  while (length(queue) > 0L) {
    current <- queue[[1L]]
    queue <- queue[-1L]
    neighbors <- character(0)
    if (include %in% c("children", "both")) {
      hit <- children_map[[current]]
      if (!is.null(hit)) {
        neighbors <- c(neighbors, hit)
      }
    }
    if (include %in% c("parents", "both")) {
      neighbors <- c(neighbors, deps_map[[current]])
    }
    for (nb in neighbors) {
      if (!(nb %in% seen)) {
        seen <- c(seen, nb)
        queue <- c(queue, nb)
      }
    }
  }

  missing <- setdiff(seen, names(deps_map))
  if (length(missing) > 0L) {
    stop(
      sprintf(
        "Build log references unknown dependencies: %s.",
        paste(sort(missing), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  seen
}

#' Read a node and all of its related nodes
#'
#' Reads the requested node plus its transitive `children` (nodes that
#' depend on it), `parents` (nodes it depends on), or `both`. Each node
#' uses the serializer recorded in the build log unless `deserializer` is
#' a function, in which case that function reads every node.
#'
#' A single unreadable node aborts the whole tree by default. Pass
#' `on_unreadable = "path"` to fall back to the artifact path for nodes that
#' fail to deserialize (for example `^pmml` model artifacts downstream), or
#' `on_unreadable = "skip"` to omit them. Both fallbacks warn naming the node
#' and the error. `return_path = TRUE` returns every path and never triggers
#' the fallback.
#'
#' @param name Name of the root node to read.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#' @param deserializer Function or `NULL`. When `NULL` (the default), each
#'   node picks its reader from its own build-log `serializer` field.
#' @param return_path Logical. If `TRUE`, returns artifact paths instead of
#'   deserialized values. Defaults to `FALSE`.
#' @param include Character. One of `"children"` (the default), `"parents"`,
#'   or `"both"`.
#' @param on_unreadable Character. One of `"error"` (the default), `"path"`,
#'   or `"skip"`.
#'
#' @return A named list mapping node name to deserialized value (or path).
#'
#' @details
#' `children` are direct and indirect dependents found by reverse lookup of
#' the build-log `dependencies` arrays. This is the helper to call when one
#' `read_node()` result is not enough and the downstream artifacts are also
#' needed. All nodes come from the single build log selected up front, so a
#' concurrent build cannot mix two snapshots mid-loop.
#'
#' @examples
#' \dontrun{
#'   tree <- read_node_tree("clean_data")
#'   tree <- read_node_tree("clean_data", include = "both")
#'   tree <- read_node_tree("clean_data", on_unreadable = "path")
#' }
#'
#' @export
read_node_tree <- function(
    name,
    which_log = NULL,
    pipeline_dir = "_pipeline",
    deserializer = NULL,
    return_path = FALSE,
    include = "children",
    on_unreadable = "error") {
  validate_scalar_string(name, "name")
  validate_scalar_string(pipeline_dir, "pipeline_dir")
  include <- match.arg(include, c("children", "parents", "both"))
  on_unreadable <- match.arg(on_unreadable, c("error", "path", "skip"))

  if (!is.null(deserializer) && !is.function(deserializer)) {
    stop("`deserializer` must be a function or NULL.", call. = FALSE)
  }

  if (!dir.exists(pipeline_dir)) {
    stop(sprintf("Pipeline directory `%s` does not exist.", pipeline_dir), call. = FALSE)
  }

  logs <- list_build_logs(pipeline_dir)
  log_file <- select_build_log(logs, which_log, pipeline_dir)
  log_path <- file.path(pipeline_dir, log_file)
  build_log <- read_build_log(log_path)
  deps_map <- build_log_deps_map(build_log$nodes)
  wanted <- closure_nodes(deps_map, name, include)

  entries <- list()
  for (entry in build_log$nodes) {
    if (is.list(entry) && !is.null(entry$node)) {
      entries[[as.character(entry$node)[[1L]]]] <- entry
    }
  }

  result <- list()
  for (node_name in wanted) {
    if (isTRUE(return_path)) {
      # Single-bracket assignment keeps NULL values instead of dropping them.
      result[node_name] <- list(read_node_entry(
        entries[[node_name]],
        node_name,
        pipeline_dir,
        deserializer,
        TRUE
      ))
      next
    }
    value <- tryCatch(
      read_node_entry(
        entries[[node_name]],
        node_name,
        pipeline_dir,
        deserializer,
        FALSE
      ),
      error = function(err) err
    )
    if (inherits(value, "error")) {
      if (on_unreadable == "error") {
        stop(conditionMessage(value), call. = FALSE)
      }
      warning(sprintf(
        "Node `%s` could not be deserialized (%s); %s.",
        node_name, conditionMessage(value),
        if (on_unreadable == "path") "returning the artifact path" else "skipping it"
      ), call. = FALSE)
      if (on_unreadable == "path") {
        result[node_name] <- list(resolve_artifact_path(
          entries[[node_name]]$path, pipeline_dir
        ))
      }
      # "skip": omit the node.
    } else {
      # Single-bracket assignment keeps NULL values instead of dropping them.
      result[node_name] <- list(value)
    }
  }
  result
}

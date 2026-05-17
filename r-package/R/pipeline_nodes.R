#' Validate a single DAG entry from the JSON structure
#'
#' Validates that the entry is a list/object, extracts the node name and
#' its list of dependencies, checking that they are non-empty strings.
#'
#' @param entry A list representing a single node's configuration from the DAG JSON.
#' @param index Integer. The 1-based index of this entry in the DAG file (used in error messages).
#' @param dag_file Character. The path to the DAG file being parsed (used in error messages).
#'
#' @return A list containing:
#'   \item{node_name}{The validated, non-empty character string node name.}
#'   \item{depends}{A sorted, unique character vector of dependency node names.}
#'
#' @keywords internal
validate_node_entry <- function(entry, index, dag_file) {
  if (!is.list(entry)) {
    stop(
      sprintf("Entry %d in `%s` must be an object.", index, dag_file),
      call. = FALSE
    )
  }

  node_name <- entry$node_name
  depends <- entry$depends

  if (is.list(depends)) {
    depends <- unlist(depends)
  }

  if (is.null(depends)) {
    depends <- character(0)
  }

  if (!is.character(node_name) || length(node_name) != 1L || is.na(node_name) || !nzchar(node_name)) {
    stop(
      sprintf("Entry %d in `%s` has an invalid `node_name`.", index, dag_file),
      call. = FALSE
    )
  }

  if (!is.character(depends) || any(is.na(depends)) || any(!nzchar(depends))) {
    stop(
      sprintf("Node `%s` in `%s` has an invalid `depends` list.", node_name, dag_file),
      call. = FALSE
    )
  }

  list(node_name = node_name, depends = unique(sort(depends)))
}

#' Get pipeline nodes and their dependencies from `_pipeline/dag.json`
#'
#' Reads a pipeline DAG definition from `_pipeline/dag.json` and returns a
#' data frame with node names and their dependencies.
#'
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#' @param dag_file Name of the DAG JSON file inside `pipeline_dir`.
#'   Defaults to `"dag.json"`.
#'
#' @return A data frame with two columns: `node` (character) and `depends`
#'   (list of character vectors).
#'
#' @details
#' The function reads the JSON file, parses its array of node definitions,
#' validates that all dependencies refer to existing nodes defined within the same
#' DAG file, and that no duplicate node names exist.
#'
#' @examples
#' \dontrun{
#'   # Assuming a pipeline has been constructed in "_pipeline"
#'   nodes <- pipeline_nodes()
#' }
#'
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

  data.frame(
    node = node_names,
    depends = I(lapply(normalized, `[[`, "depends")),
    stringsAsFactors = FALSE
  )
}

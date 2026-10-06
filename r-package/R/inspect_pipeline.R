#' Derive a display status from a build-log node entry
#'
#' Prefers the `status` string when present, else maps `success`
#' (logical or `"true"`/`"false"` string) to `"Completed"`/`"SoftFailed"`.
#'
#' @param entry List. One node entry from the build log.
#'
#' @return Character scalar or NA.
#'
#' @keywords internal
inspect_status_of <- function(entry) {
  status <- entry$status
  if (is.character(status) && length(status) == 1L && !is.na(status) && nzchar(trimws(status))) {
    return(trimws(status))
  }
  success <- entry$success
  if (is.logical(success) && length(success) == 1L && !is.na(success)) {
    return(if (isTRUE(success)) "Completed" else "SoftFailed")
  }
  if (is.character(success) && length(success) == 1L && !is.na(success) && nzchar(trimws(success))) {
    return(if (tolower(trimws(success)) == "true") "Completed" else "SoftFailed")
  }
  NA_character_
}

#' Return trimmed text or NA for missing values
#'
#' @param x Any value from the build log.
#'
#' @return Character scalar or NA.
#'
#' @keywords internal
inspect_text_or_na <- function(x) {
  if (is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))) {
    trimws(x)
  } else {
    NA_character_
  }
}

#' Inspect pipeline nodes and their latest build status
#'
#' Reads the selected build log and returns one row per node with its runtime,
#' serializer, dependencies, status, class, and resolved artifact path. When
#' no build logs exist, falls back to the static DAG file with `status` set
#' to `"unbuilt"`.
#'
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param dag_file Name of the DAG JSON file used only when no build logs
#'   exist. Defaults to `"dag.json"`.
#'
#' @return A data frame with columns `node`, `runtime`, `serializer`,
#'   `depends` (list of character vectors), `status`, `class`, and `path`.
#'
#' @examples
#' \dontrun{
#'   tbl <- inspect_pipeline()
#'   print(tbl)
#' }
#'
#' @export
inspect_pipeline <- function(
    pipeline_dir = "_pipeline",
    which_log = NULL,
    dag_file = "dag.json") {
  validate_scalar_string(pipeline_dir, "pipeline_dir")
  validate_scalar_string(dag_file, "dag_file")

  if (!dir.exists(pipeline_dir)) {
    stop(sprintf("Pipeline directory `%s` does not exist.", pipeline_dir), call. = FALSE)
  }

  logs <- list_build_logs(pipeline_dir)
  if (!length(logs)) {
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
    return(data.frame(
      node = vapply(normalized, `[[`, character(1), "node_name"),
      runtime = NA_character_,
      serializer = NA_character_,
      depends = I(lapply(normalized, `[[`, "depends")),
      status = "unbuilt",
      class = NA_character_,
      path = NA_character_,
      stringsAsFactors = FALSE
    ))
  }

  log_file <- select_build_log(logs, which_log, pipeline_dir)
  log_path <- file.path(pipeline_dir, log_file)
  build_log <- read_build_log(log_path)
  nodes <- build_log$nodes
  if (!is.list(nodes)) {
    stop(sprintf("Build log `%s` does not contain a `nodes` array.", log_file), call. = FALSE)
  }

  rows <- list()
  for (entry in nodes) {
    if (!is.list(entry) || is.null(entry$node)) {
      next
    }
    nm <- as.character(entry$node)[[1L]]
    if (is.na(nm) || !nzchar(nm)) {
      next
    }
    deps <- entry$dependencies
    if (is.null(deps)) {
      deps <- character(0)
    } else if (is.list(deps)) {
      deps <- unlist(deps)
    }
    deps <- as.character(deps)
    deps <- sort(unique(deps[!is.na(deps) & nzchar(deps)]))
    artifact <- tryCatch(
      resolve_artifact_path(entry$path, pipeline_dir),
      error = function(err) NA_character_
    )
    rows[[length(rows) + 1L]] <- list(
      node = nm,
      runtime = inspect_text_or_na(entry$runtime),
      serializer = inspect_text_or_na(entry$serializer),
      depends = deps,
      status = inspect_status_of(entry),
      class = inspect_text_or_na(entry$class),
      path = if (length(artifact) == 1L && !is.na(artifact)) artifact else NA_character_
    )
  }

  data.frame(
    node = vapply(rows, `[[`, character(1), "node"),
    runtime = vapply(rows, `[[`, character(1), "runtime"),
    serializer = vapply(rows, `[[`, character(1), "serializer"),
    depends = I(lapply(rows, `[[`, "depends")),
    status = vapply(rows, `[[`, character(1), "status"),
    class = vapply(rows, `[[`, character(1), "class"),
    path = vapply(rows, `[[`, character(1), "path"),
    stringsAsFactors = FALSE
  )
}

#' Load one node entry plus the dependency map from a single build log
#'
#' Selects the build log once so callers never mix two snapshots.
#'
#' @param name Character. Node name.
#' @param which_log Character or NULL. Log selection regex.
#' @param pipeline_dir Character. Pipeline directory.
#'
#' @return List with `entry`, `log_file`, and `deps_map`.
#'
#' @keywords internal
load_inspect_entry <- function(name, which_log, pipeline_dir) {
  logs <- list_build_logs(pipeline_dir)
  log_file <- select_build_log(logs, which_log, pipeline_dir)
  build_log <- read_build_log(file.path(pipeline_dir, log_file))
  nodes <- build_log$nodes
  if (!is.list(nodes)) {
    stop(sprintf("Build log `%s` does not contain a `nodes` array.", log_file), call. = FALSE)
  }
  list(
    entry = find_node_entry(nodes, name, log_file),
    log_file = log_file,
    deps_map = build_log_deps_map(nodes)
  )
}

#' Parse a VError JSON artifact, or NULL when it is not one
#'
#' Foreign-runtime failures (R, Python, Julia, shell) are stored as VError
#' JSON with `type`, `code`, `message`, `context`, and `location` fields, so
#' an R error message reads the same from any language.
#'
#' @param artifact_path Character. Absolute artifact path.
#'
#' @return Named list with `code`, `message`, `context`, `location`, or NULL.
#'
#' @keywords internal
verror_from_file <- function(artifact_path) {
  payload <- tryCatch(
    jsonlite::fromJSON(artifact_path, simplifyVector = FALSE),
    error = function(err) NULL
  )
  if (!is.list(payload) || !identical(payload$type, "VError")) {
    return(NULL)
  }
  code <- payload$code
  message <- payload$message
  context <- payload$context
  location <- payload$location
  list(
    code = if (is.character(code) && length(code) == 1L && !is.na(code) && nzchar(code)) code else "RuntimeError",
    message = if (is.character(message) && length(message) == 1L && !is.na(message)) message else "Unknown error",
    context = if (is.list(context)) context else NULL,
    location = if (is.list(location)) location else NULL
  )
}

#' Whether the log entry shows failure (or shows nothing at all)
#'
#' Positively successful nodes skip the artifact read, so large artifacts are
#' never loaded just to check for errors.
#'
#' @param entry List. One node entry from the build log.
#'
#' @return Logical scalar.
#'
#' @keywords internal
looks_failed <- function(entry) {
  # A VError/Error class always counts as failed, even when status says
  # otherwise: T soft errors are values, so a stored error can sit beside
  # any status string. Any other class falls through to status below.
  class_val <- entry$class
  if (is.character(class_val) && length(class_val) == 1L && !is.na(class_val) &&
      nzchar(trimws(class_val)) && trimws(class_val) %in% c("VError", "Error")) {
    return(TRUE)
  }
  status <- entry$status
  if (is.character(status) && length(status) == 1L && !is.na(status) && nzchar(trimws(status))) {
    return(trimws(status) %in% c("Errored", "SoftFailed"))
  }
  success <- entry$success
  if (is.logical(success) && length(success) == 1L && !is.na(success)) {
    return(!isTRUE(success))
  }
  if (is.character(success) && length(success) == 1L && !is.na(success) && nzchar(trimws(success))) {
    return(tolower(trimws(success)) != "true")
  }
  TRUE
}

#' Build a node error from an already-loaded entry (no log re-read)
#'
#' @param entry List. One node entry from the build log.
#' @param pipeline_dir Character. Pipeline directory.
#' @param default_code Character or NULL. Fallback code when the entry
#'   carries a message but no code.
#'
#' @return Named list or NULL when the node has no error.
#'
#' @keywords internal
error_of_entry <- function(entry, pipeline_dir, default_code = NULL) {
  code <- entry$error_code
  message <- entry$error_message
  code_ok <- is.character(code) && length(code) == 1L && !is.na(code) && nzchar(code)
  msg_ok <- is.character(message) && length(message) == 1L && !is.na(message) && nzchar(message)
  if (!looks_failed(entry)) {
    if (!code_ok && !msg_ok) {
      return(NULL)
    }
  } else {
    artifact_path <- tryCatch(
      resolve_artifact_path(entry$path, pipeline_dir),
      error = function(err) NULL
    )
    if (!is.null(artifact_path)) {
      verror <- verror_from_file(artifact_path)
      if (!is.null(verror)) {
        return(verror)
      }
    }
  }
  if (code_ok || msg_ok) {
    fallback <- if (is.character(default_code) && length(default_code) == 1L &&
      !is.na(default_code) && nzchar(default_code)) default_code else "Error"
    return(list(
      code = if (code_ok) code else fallback,
      message = if (msg_ok) message else "",
      context = NULL,
      location = NULL
    ))
  }
  NULL
}

#' Require a failed node and return its error, else stop
#'
#' Mirrors T, where `error_msg()` on a healthy node is a `TypeError`.
#'
#' @param entry List. One node entry from the build log.
#' @param name Character. Node name.
#' @param pipeline_dir Character. Pipeline directory.
#' @param func Character. Calling function name for the message.
#'
#' @return Named list with `code`, `message`, `context`, `location`.
#'
#' @keywords internal
require_node_error <- function(entry, name, pipeline_dir, func) {
  verror <- error_of_entry(entry, pipeline_dir)
  if (is.null(verror)) {
    stop(sprintf("Function `%s` expects a failed node, but node `%s` has no error.", func, name), call. = FALSE)
  }
  verror
}

#' Read a failed node's error as plain data
#'
#' Shared lookup for `error_msg()`, `error_code()`, and `error_context()`.
#' Foreign-runtime failures are stored as VError JSON, so an R error message
#' reads the same from R, Python, or Julia.
#'
#' @param name Name of the node to inspect.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#'
#' @return Named list with `code`, `message`, `context`, `location`.
#'
#' @keywords internal
lookup_node_error <- function(name, which_log, pipeline_dir, func) {
  validate_scalar_string(name, "name")
  validate_scalar_string(pipeline_dir, "pipeline_dir")

  if (!dir.exists(pipeline_dir)) {
    stop(sprintf("Pipeline directory `%s` does not exist.", pipeline_dir), call. = FALSE)
  }

  loaded <- load_inspect_entry(name, which_log, pipeline_dir)
  require_node_error(loaded$entry, name, pipeline_dir, func)
}

#' Get a failed node's human-readable error message
#'
#' Mirrors T's `error_msg()`.
#'
#' @param name Name of the node to inspect.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#'
#' @return Character. The error message.
#'
#' @examples
#' \dontrun{
#'   msg <- error_msg("model")
#'   print(msg)
#' }
#'
#' @export
error_msg <- function(name, which_log = NULL, pipeline_dir = "_pipeline") {
  lookup_node_error(name, which_log, pipeline_dir, "error_msg")$message
}

#' Get a failed node's error code
#'
#' Mirrors T's `error_code()`.
#'
#' @param name Name of the node to inspect.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#'
#' @return Character. The error code (for example `"ValueError"`).
#'
#' @examples
#' \dontrun{
#'   code <- error_code("model")
#'   print(code)
#' }
#'
#' @export
error_code <- function(name, which_log = NULL, pipeline_dir = "_pipeline") {
  lookup_node_error(name, which_log, pipeline_dir, "error_code")$code
}

#' Get a failed node's error context
#'
#' Mirrors T's `error_context()`.
#'
#' @param name Name of the node to inspect.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#'
#' @return Named list. The error context, or an empty list.
#'
#' @examples
#' \dontrun{
#'   ctx <- error_context("model")
#'   print(ctx)
#' }
#'
#' @export
error_context <- function(name, which_log = NULL, pipeline_dir = "_pipeline") {
  context <- lookup_node_error(name, which_log, pipeline_dir, "error_context")$context
  if (is.list(context)) context else list()
}

#' Get a node's formatted warnings
#'
#' Upstream warnings are prefixed with the source node name, and multiple
#' warnings join with `". Furthermore, "`. Returns `""` when there are none.
#' Mirrors T's `warning_msg()`.
#'
#' @param name Name of the node to inspect.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#'
#' @return Character. The formatted warning message, or `""`.
#'
#' @examples
#' \dontrun{
#'   msg <- warning_msg("model")
#'   print(msg)
#' }
#'
#' @export
warning_msg <- function(name, which_log = NULL, pipeline_dir = "_pipeline") {
  validate_scalar_string(name, "name")
  validate_scalar_string(pipeline_dir, "pipeline_dir")

  if (!dir.exists(pipeline_dir)) {
    stop(sprintf("Pipeline directory `%s` does not exist.", pipeline_dir), call. = FALSE)
  }

  logs <- list_build_logs(pipeline_dir)
  log_file <- select_build_log(logs, which_log, pipeline_dir)
  build_log <- read_build_log(file.path(pipeline_dir, log_file))
  nodes <- build_log$nodes
  if (!is.list(nodes)) {
    stop(sprintf("Build log `%s` does not contain a `nodes` array.", log_file), call. = FALSE)
  }
  find_node_entry(nodes, name, log_file)
  deps_map <- build_log_deps_map(nodes)

  entries <- list()
  for (entry in nodes) {
    if (is.list(entry) && !is.null(entry$node)) {
      entries[[as.character(entry$node)[[1L]]]] <- entry
    }
  }

  collect <- function(node_name, prefix) {
    rows <- frames_warning_rows(node_name, entries[[node_name]], pipeline_dir)
    vapply(rows, function(row) {
      if (nzchar(prefix)) sprintf("%s: %s", prefix, row$message) else row$message
    }, character(1))
  }

  messages <- collect(name, "")
  for (parent in closure_nodes(deps_map, name, "parents")[-1L]) {
    messages <- c(messages, collect(
      parent, sprintf("Ancestor node '%s' reported following warning", parent)))
  }
  paste(messages, collapse = ". Furthermore, ")
}

#' Inspect one node's metadata, lineage, error, and warnings
#'
#' @param name Name of the node to inspect.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#'
#' @return Named list with `name`, `runtime`, `serializer`, `dependencies`,
#'   `children` (direct dependents), `status`, `class`, `path`, `error`
#'   (`code`/`message`/`context`/`location` record or NULL), and `warnings`
#'   (list of `code`/`message` lists).
#'
#' @examples
#' \dontrun{
#'   info <- inspect_node("model")
#'   print(info$runtime)
#' }
#'
#' @export
inspect_node <- function(name, which_log = NULL, pipeline_dir = "_pipeline") {
  validate_scalar_string(name, "name")
  validate_scalar_string(pipeline_dir, "pipeline_dir")

  if (!dir.exists(pipeline_dir)) {
    stop(sprintf("Pipeline directory `%s` does not exist.", pipeline_dir), call. = FALSE)
  }

  loaded <- load_inspect_entry(name, which_log, pipeline_dir)
  entry <- loaded$entry
  deps_map <- loaded$deps_map

  deps <- entry$dependencies
  if (is.null(deps)) {
    deps <- character(0)
  } else if (is.list(deps)) {
    deps <- unlist(deps)
  }
  deps <- sort(unique(as.character(deps)), method = "radix")
  deps <- deps[!is.na(deps) & nzchar(deps)]

  children <- sort(names(deps_map)[vapply(
    deps_map, function(ds) name %in% ds, logical(1)
  )], method = "radix")

  warn_rows <- frames_warning_rows(name, entry, pipeline_dir)
  warnings <- lapply(warn_rows, function(row) list(code = row$code, message = row$message))

  list(
    name = name,
    runtime = inspect_text_or_na(entry$runtime),
    serializer = inspect_text_or_na(entry$serializer),
    dependencies = deps,
    children = children,
    status = frames_status_of(entry),
    class = inspect_text_or_na(entry$class),
    path = tryCatch(
      resolve_artifact_path(entry$path, pipeline_dir),
      error = function(err) NA_character_
    ),
    error = error_of_entry(entry, pipeline_dir),
    warnings = warnings
  )
}

#' List a node's transitive parents and children (names only)
#'
#' @param name Name of the node.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#' @param direction One of `"parents"`, `"children"`, or `"both"` (the
#'   default).
#'
#' @return Named list with `parents` (nearest first) and `children` (nearest
#'   first). Only the requested directions are filled; the other is empty.
#'
#' @examples
#' \dontrun{
#'   lin <- lineage("model")
#'   print(lin$parents)
#' }
#'
#' @export
lineage <- function(name, which_log = NULL, pipeline_dir = "_pipeline", direction = "both") {
  validate_scalar_string(name, "name")
  validate_scalar_string(pipeline_dir, "pipeline_dir")
  direction <- match.arg(direction, c("parents", "children", "both"))

  if (!dir.exists(pipeline_dir)) {
    stop(sprintf("Pipeline directory `%s` does not exist.", pipeline_dir), call. = FALSE)
  }

  loaded <- load_inspect_entry(name, which_log, pipeline_dir)
  deps_map <- loaded$deps_map

  parents <- character(0)
  children <- character(0)
  if (direction %in% c("parents", "both")) {
    parents <- closure_nodes(deps_map, name, "parents")[-1L]
  }
  if (direction %in% c("children", "both")) {
    children <- closure_nodes(deps_map, name, "children")[-1L]
  }
  list(parents = parents, children = children)
}

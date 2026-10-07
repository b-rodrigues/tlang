#' Keep the last non-empty message line, truncated like T
#'
#' @param msg Any message value from the build log.
#'
#' @return Character scalar.
#'
#' @keywords internal
frames_clean_message <- function(msg) {
  if (!is.character(msg) || length(msg) != 1L || is.na(msg)) {
    return("")
  }
  lines <- trimws(strsplit(msg, "\n", fixed = TRUE)[[1L]])
  lines <- lines[nzchar(lines)]
  if (!length(lines)) {
    return("")
  }
  last <- lines[[length(lines)]]
  if (nchar(last) > 100) {
    paste0(substr(last, 1L, 97L), "...")
  } else {
    last
  }
}

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
frames_status_of <- function(entry) {
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

#' Parse a duration value to numeric
#'
#' @param entry List. One node entry from the build log.
#'
#' @return Numeric scalar or NA.
#'
#' @keywords internal
frames_duration_of <- function(entry) {
  duration <- entry$duration
  if (is.logical(duration) || is.null(duration)) {
    return(NA_real_)
  }
  if (is.numeric(duration) && length(duration) == 1L && !is.na(duration)) {
    return(as.numeric(duration))
  }
  if (is.character(duration) && length(duration) == 1L && !is.na(duration) && nzchar(trimws(duration))) {
    parsed <- suppressWarnings(as.numeric(trimws(duration)))
    if (!is.na(parsed)) {
      return(parsed)
    }
  }
  NA_real_
}

#' Read warning rows from a per-artifact `warnings` sidecar
#'
#' The logged path is resolved against `pipeline_dir` first, so relative log
#' paths still find their sidecar.
#'
#' @param name Character. Node name.
#' @param entry List. One node entry from the build log.
#' @param pipeline_dir Character. Pipeline directory for path resolution.
#'
#' @return List of warning row lists.
#'
#' @keywords internal
frames_warning_rows <- function(name, entry, pipeline_dir) {
  flag <- entry$warnings
  has_warnings <- isTRUE(flag) ||
    (is.character(flag) && length(flag) == 1L && !is.na(flag) && tolower(trimws(flag)) == "true")
  if (!has_warnings) {
    return(list())
  }
  artifact_path <- tryCatch(
    resolve_artifact_path(entry$path, pipeline_dir),
    error = function(err) NULL
  )
  if (is.null(artifact_path)) {
    return(list())
  }
  sidecar <- file.path(dirname(artifact_path), "warnings")
  if (!file.exists(sidecar)) {
    return(list())
  }
  items <- tryCatch(
    jsonlite::fromJSON(sidecar, simplifyVector = FALSE),
    error = function(err) NULL
  )
  if (!is.list(items)) {
    return(list())
  }
  rows <- list()
  for (item in items) {
    if (is.character(item) && length(item) == 1L && !is.na(item)) {
      rows[[length(rows) + 1L]] <- list(node = name, status = "Warning", code = "Generic", message = item)
    } else if (is.list(item)) {
      kind <- item$kind
      msg <- item$message
      rows[[length(rows) + 1L]] <- list(
        node = name,
        status = "Warning",
        code = if (is.character(kind) && length(kind) == 1L && !is.na(kind) && nzchar(kind)) kind else "Generic",
        message = if (is.character(msg) && length(msg) == 1L && !is.na(msg)) msg else ""
      )
    }
  }
  rows
}

#' List build logs in the pipeline directory, newest first
#'
#' Returns one row per `build_log_*.json` file with its filename, local
#' modification time, size in KB, and logged pipeline name. Mirrors T's
#' `list_logs()`.
#'
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#'
#' @return A data frame with columns `filename`, `modification_time`,
#'   `size_kb`, and `pipeline`.
#'
#' @examples
#' \dontrun{
#'   logs <- list_logs()
#'   print(logs)
#' }
#'
#' @export
list_logs <- function(pipeline_dir = "_pipeline") {
  validate_scalar_string(pipeline_dir, "pipeline_dir")

  if (!dir.exists(pipeline_dir)) {
    stop(sprintf("Pipeline directory `%s` does not exist.", pipeline_dir), call. = FALSE)
  }

  logs <- list_build_logs(pipeline_dir)
  filenames <- character()
  mtimes <- character()
  sizes <- numeric()
  pipelines <- character()
  for (log_file in logs) {
    full <- file.path(pipeline_dir, log_file)
    info <- file.info(full)
    logged <- tryCatch(
      jsonlite::fromJSON(full, simplifyVector = FALSE),
      error = function(err) NULL
    )
    pipeline <- NA_character_
    if (is.list(logged) && is.character(logged$pipeline) && length(logged$pipeline) == 1L && !is.na(logged$pipeline)) {
      pipeline <- logged$pipeline
    }
    filenames <- c(filenames, log_file)
    mtimes <- c(mtimes, format(info$mtime, "%Y-%m-%d %H:%M:%S"))
    sizes <- c(sizes, round(info$size / 1024, 2))
    pipelines <- c(pipelines, pipeline)
  }

  data.frame(
    filename = filenames,
    modification_time = mtimes,
    size_kb = sizes,
    pipeline = pipelines,
    stringsAsFactors = FALSE
  )
}

#' Tabulate one build log as per-node rows
#'
#' Each row has `name`, `status`, `duration`, and `path`. Mirrors T's
#' `build_log_to_frame()`.
#'
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#'
#' @return A data frame with columns `name`, `status`, `duration`, and `path`.
#'
#' @examples
#' \dontrun{
#'   tbl <- build_log_to_frame()
#'   print(tbl)
#' }
#'
#' @export
build_log_to_frame <- function(pipeline_dir = "_pipeline", which_log = NULL) {
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

  names <- character()
  statuses <- character()
  durations <- numeric()
  paths <- character()
  for (entry in nodes) {
    if (!is.list(entry) || is.null(entry$node)) {
      next
    }
    nm <- as.character(entry$node)[[1L]]
    if (is.na(nm) || !nzchar(nm)) {
      next
    }
    path <- if (is.character(entry$path) && length(entry$path) == 1L && !is.na(entry$path)) entry$path else NA_character_
    names <- c(names, nm)
    statuses <- c(statuses, frames_status_of(entry))
    durations <- c(durations, frames_duration_of(entry))
    paths <- c(paths, path)
  }

  data.frame(
    name = names,
    status = statuses,
    duration = durations,
    path = paths,
    stringsAsFactors = FALSE
  )
}

#' Gather error and warning rows from one build log
#'
#' Each row has `node`, `status` (`Error`/`Warning`), `code`, and `message`.
#' Soft-failed nodes read the VError artifact first, so a message that lives
#' only in the artifact (not the log) is still reported. Warning rows come
#' from the per-artifact `warnings` sidecar. Mirrors T's
#' `collect_exceptions()`.
#'
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#'
#' @return A data frame with columns `node`, `status`, `code`, and `message`.
#'
#' @examples
#' \dontrun{
#'   errs <- collect_exceptions()
#'   print(errs)
#' }
#'
#' @export
collect_exceptions <- function(pipeline_dir = "_pipeline", which_log = NULL) {
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

  rows <- list()
  for (entry in nodes) {
    if (!is.list(entry) || is.null(entry$node)) {
      next
    }
    nm <- as.character(entry$node)[[1L]]
    if (is.na(nm) || !nzchar(nm)) {
      next
    }
    status <- frames_status_of(entry)
    class_val <- if (is.character(entry$class) && length(entry$class) == 1L && !is.na(entry$class)) entry$class else ""
    if (identical(status, "Errored")) {
      code <- entry$error_code
      msg <- frames_clean_message(entry$error_message)
      rows[[length(rows) + 1L]] <- list(
        node = nm,
        status = "Error",
        code = if (is.character(code) && length(code) == 1L && !is.na(code) && nzchar(code)) code else "NixError",
        message = if (nzchar(msg)) msg else "Nix build failed."
      )
    } else if (identical(status, "SoftFailed") || class_val %in% c("VError", "Error")) {
      err <- error_of_entry(entry, pipeline_dir,
        default_code = if (nzchar(class_val)) class_val else NULL)
      if (is.null(err)) {
        code <- class_val
        msg <- ""
      } else {
        code <- err$code
        msg <- err$message
      }
      clean <- frames_clean_message(msg)
      rows[[length(rows) + 1L]] <- list(
        node = nm,
        status = "Error",
        code = if (nzchar(code)) code else if (nzchar(class_val)) class_val else "Error",
        message = if (nzchar(clean)) clean else "Node failed with a soft error."
      )
    }
    rows <- c(rows, frames_warning_rows(nm, entry, pipeline_dir))
  }

  data.frame(
    node = vapply(rows, `[[`, character(1), "node"),
    status = vapply(rows, `[[`, character(1), "status"),
    code = vapply(rows, `[[`, character(1), "code"),
    message = vapply(rows, `[[`, character(1), "message"),
    stringsAsFactors = FALSE
  )
}

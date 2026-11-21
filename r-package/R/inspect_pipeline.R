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
#'   `dependencies` (list of character vectors), `status`, `class`, and `path`.
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
      dependencies = I(lapply(normalized, `[[`, "depends")),
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
    deps <- sort(unique(deps[!is.na(deps) & nzchar(deps)]), method = "radix")
    artifact <- tryCatch(
      resolve_artifact_path(entry$path, pipeline_dir),
      error = function(err) NA_character_
    )
    rows[[length(rows) + 1L]] <- list(
      node = nm,
      runtime = inspect_text_or_na(entry$runtime),
      serializer = inspect_text_or_na(entry$serializer),
      dependencies = deps,
      status = frames_status_of(entry),
      class = inspect_text_or_na(entry$class),
      path = if (length(artifact) == 1L && !is.na(artifact)) artifact else NA_character_
    )
  }

  data.frame(
    node = vapply(rows, `[[`, character(1), "node"),
    runtime = vapply(rows, `[[`, character(1), "runtime"),
    serializer = vapply(rows, `[[`, character(1), "serializer"),
    dependencies = I(lapply(rows, `[[`, "dependencies")),
    status = vapply(rows, `[[`, character(1), "status"),
    class = vapply(rows, `[[`, character(1), "class"),
    path = vapply(rows, `[[`, character(1), "path"),
    stringsAsFactors = FALSE
  )
}

#' Index the selected build log's entries by node name
#'
#' @param pipeline_dir Path to the pipeline directory.
#' @param which_log Optional log regex.
#'
#' @return Named list of node entries; empty when no build log exists or the
#'   log cannot be read.
#'
#' @keywords internal
overview_entries <- function(pipeline_dir, which_log) {
  logs <- list_build_logs(pipeline_dir)
  if (!length(logs)) {
    return(list())
  }
  log_file <- select_build_log(logs, which_log, pipeline_dir)
  build_log <- tryCatch(
    read_build_log(file.path(pipeline_dir, log_file)),
    error = function(err) NULL
  )
  if (is.null(build_log) || !is.list(build_log$nodes)) {
    return(list())
  }
  out <- list()
  for (entry in build_log$nodes) {
    if (!is.list(entry) || is.null(entry$node)) {
      next
    }
    nm <- as.character(entry$node)[[1L]]
    if (is.na(nm) || !nzchar(nm)) {
      next
    }
    out[[nm]] <- entry
  }
  out
}

#' Pipeline overview, failed first
#'
#' Mirrors T pipeline_overview. Returns one row per node, failed first.
#' Failed nodes carry `status = "Errored"` and `class = "Error"`; completed
#' nodes carry `"Built"`. Unbuilt and skipped nodes keep their own status
#' instead of being reported as built.
#'
#' @param pipeline_dir Path to pipeline dir.
#' @param which_log Optional log regex.
#' @param only Optional filter: `"failed"`, `"built"`, `"unbuilt"`, or
#'   `"all"`. Defaults to all rows, failed first.
#' @return Data frame with columns `name`, `runtime`, `serializer`,
#'   `dependencies`, `status`, `class`, `path`, `error_code`, and
#'   `error_message`. Failed nodes carry the entry's error in `error_code` and
#'   `error_message` (NA for healthy rows).
#' @export
pipeline_overview <- function(pipeline_dir = "_pipeline", which_log = NULL, only = NULL) {
  key <- NULL
  if (!is.null(only)) {
    if (!is.character(only) || length(only) != 1L || is.na(only)) {
      stop("only must be a single string.", call. = FALSE)
    }
    key <- tolower(trimws(only))
    if (!key %in% c("failed", "errored", "built", "completed", "unbuilt", "pending", "all")) {
      stop(sprintf("pipeline_overview: only must be failed, built, unbuilt, or all, but got \"%s\".", only), call. = FALSE)
    }
  }
  rows <- inspect_pipeline(pipeline_dir = pipeline_dir, which_log = which_log)
  if (nrow(rows) == 0L) {
    return(data.frame(
      name = character(0),
      runtime = character(0),
      serializer = character(0),
      dependencies = I(list()),
      status = character(0),
      class = character(0),
      path = character(0),
      error_code = character(0),
      error_message = character(0),
      stringsAsFactors = FALSE
    ))
  }
  entries <- overview_entries(pipeline_dir, which_log)
  errs <- lapply(rows$node, function(nm) {
    entry <- if (is.character(nm) && length(nm) == 1L && !is.na(nm) && nzchar(nm)) {
      entries[[nm]]
    } else {
      NULL
    }
    if (is.null(entry)) {
      return(NULL)
    }
    tryCatch(error_of_entry(entry, pipeline_dir), error = function(err) NULL)
  })
  err_field <- function(field) {
    vapply(errs, function(err) {
      if (is.null(err)) {
        return(NA_character_)
      }
      value <- err[[field]]
      if (is.character(value) && length(value) == 1L && !is.na(value)) {
        value
      } else {
        NA_character_
      }
    }, character(1))
  }
  st <- tolower(ifelse(is.na(rows$status), "", rows$status))
  cls <- tolower(ifelse(is.na(rows$class), "", rows$class))
  has_error <- !vapply(errs, is.null, logical(1))
  failed <- has_error | st %in% c("errored", "softfailed") | cls %in% c("error", "verror")
  built <- st %in% c("completed", "built", "cached")
  status <- ifelse(failed, "Errored",
                   ifelse(built, "Built",
                          ifelse(nzchar(st), rows$status, "Unbuilt")))
  overview <- data.frame(
    name = rows$node,
    runtime = rows$runtime,
    serializer = rows$serializer,
    dependencies = I(rows$dependencies),
    status = status,
    class = ifelse(failed, "Error", rows$class),
    path = ifelse(failed, NA_character_, rows$path),
    error_code = err_field("code"),
    error_message = err_field("message"),
    stringsAsFactors = FALSE
  )
  ordered <- rbind(overview[overview$status == "Errored", , drop = FALSE],
                   overview[overview$status != "Errored", , drop = FALSE])
  if (is.null(key) || key == "all") return(ordered)
  if (key %in% c("failed", "errored")) {
    return(ordered[ordered$status == "Errored", , drop = FALSE])
  }
  if (key %in% c("built", "completed")) {
    return(ordered[ordered$status == "Built", , drop = FALSE])
  }
  ordered[ordered$status %in% c("Unbuilt", "Pending", "Skipped", "NA"), , drop = FALSE]
}

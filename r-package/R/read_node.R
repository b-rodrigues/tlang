validate_scalar_string <- function(x, arg) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    stop(sprintf("`%s` must be a non-empty string.", arg), call. = FALSE)
  }
}

list_build_logs <- function(pipeline_dir) {
  logs <- list.files(
    pipeline_dir,
    pattern = "^build_log_.*\\.json$",
    full.names = FALSE
  )
  logs <- sort(logs, decreasing = TRUE)

  mocked_logs <- c("build_log_ocaml_mock.json", "build_log_legacy_version.json")
  if (length(logs) > 1L && any(!logs %in% mocked_logs)) {
    logs <- logs[!logs %in% mocked_logs]
  }

  logs
}

select_build_log <- function(logs, which_log, pipeline_dir) {
  if (is.null(which_log)) {
    if (length(logs) == 0L) {
      stop(
        sprintf(
          "No build logs found in `%s`. Build the pipeline first.",
          pipeline_dir
        ),
        call. = FALSE
      )
    }

    return(logs[[1L]])
  }

  validate_scalar_string(which_log, "which_log")

  matches <- tryCatch(
    grep(which_log, logs, value = TRUE),
    error = function(err) {
      stop(
        sprintf(
          "Invalid regular expression for `which_log`: %s",
          conditionMessage(err)
        ),
        call. = FALSE
      )
    }
  )

  if (length(matches) == 0L) {
    stop(
      sprintf(
        "No build logs found in `%s` matching \"%s\".",
        pipeline_dir,
        which_log
      ),
      call. = FALSE
    )
  }

  matches[[1L]]
}

read_build_log <- function(log_path) {
  tryCatch(
    jsonlite::fromJSON(log_path, simplifyVector = FALSE),
    error = function(err) {
      stop(
        sprintf(
          "Failed to read build log `%s`: %s",
          basename(log_path),
          conditionMessage(err)
        ),
        call. = FALSE
      )
    }
  )
}

find_node_entry <- function(nodes, name, log_file) {
  if (!is.list(nodes)) {
    stop(
      sprintf("Build log `%s` does not contain a `nodes` array.", log_file),
      call. = FALSE
    )
  }

  for (entry in nodes) {
    if (is.list(entry) && identical(entry$node, name)) {
      return(entry)
    }
  }

  stop(
    sprintf("Node `%s` not found in build log `%s`.", name, log_file),
    call. = FALSE
  )
}

resolve_artifact_path <- function(path, pipeline_dir) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("Node entry does not contain a valid artifact path.", call. = FALSE)
  }

  if (grepl("^(/|[A-Za-z]:[/\\\\])", path)) {
    return(path)
  }

  normalizePath(
    file.path(dirname(pipeline_dir), path),
    winslash = "/",
    mustWork = FALSE
  )
}

#' Read a node artifact from a built T pipeline
#'
#' Reads the latest build log (or a matching historical one) from the
#' `'_pipeline/'` directory, locates the requested node, and deserializes the
#' node artifact.
#'
#' @param name Name of the node to read.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#' @param deserializer Function used to deserialize the artifact path. Defaults
#'   to [base::readRDS()].
#'
#' @return The deserialized node artifact.
#' @export
read_node <- function(
    name,
    which_log = NULL,
    pipeline_dir = "_pipeline",
    deserializer = readRDS) {
  validate_scalar_string(name, "name")
  validate_scalar_string(pipeline_dir, "pipeline_dir")

  if (!dir.exists(pipeline_dir)) {
    stop(
      sprintf("Pipeline directory `%s` does not exist.", pipeline_dir),
      call. = FALSE
    )
  }

  if (!is.function(deserializer)) {
    stop("`deserializer` must be a function.", call. = FALSE)
  }

  logs <- list_build_logs(pipeline_dir)
  log_file <- select_build_log(logs, which_log, pipeline_dir)
  log_path <- file.path(pipeline_dir, log_file)
  build_log <- read_build_log(log_path)
  node_entry <- find_node_entry(build_log$nodes, name, log_file)
  artifact_path <- resolve_artifact_path(node_entry$path, pipeline_dir)

  tryCatch(
    deserializer(artifact_path),
    error = function(err) {
      stop(
        sprintf(
          "Failed to deserialize node `%s` from `%s`: %s",
          name,
          artifact_path,
          conditionMessage(err)
        ),
        call. = FALSE
      )
    }
  )
}

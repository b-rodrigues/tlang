#' Validate that a value is a scalar, non-empty, and non-NA character string
#'
#' @param x The value to check.
#' @param arg Character. The argument name to use in the error message.
#'
#' @return None. Throws an error if the validation fails.
#'
#' @keywords internal
validate_scalar_string <- function(x, arg) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    stop(sprintf("`%s` must be a non-empty string.", arg), call. = FALSE)
  }
}

#' List build logs in the pipeline directory, sorted reverse-alphabetically
#'
#' Searches the specified pipeline directory for build log JSON files, sorts them,
#' and filters out fixture logs if this is executed within the project repository checkout.
#'
#' @param pipeline_dir Character. The path to the pipeline directory.
#'
#' @return A sorted character vector of build log filenames.
#'
#' @keywords internal
list_build_logs <- function(pipeline_dir) {
  logs <- list.files(
    pipeline_dir,
    pattern = "^build_log_.*\\.json$",
    full.names = FALSE
  )
  logs <- sort(logs, decreasing = TRUE)

  builder_logs_ml_path <- file.path(dirname(pipeline_dir), "src", "pipeline", "builder_logs.ml")

  # Mirror T's fixture-log filtering only when reading from a repository
  # checkout, where these internal fixture logs can live beside real build logs.
  fixture_logs <- c("build_log_ocaml_mock.json", "build_log_legacy_version.json")
  if (file.exists(builder_logs_ml_path) && length(logs) > 1L && any(!logs %in% fixture_logs)) {
    logs <- logs[!logs %in% fixture_logs]
  }

  logs
}

#' Select a build log from a list of logs
#'
#' Selects the latest log file if `which_log` is `NULL`, or selects the first
#' log file matching the regular expression `which_log`.
#'
#' @param logs Character vector of available build log filenames.
#' @param which_log Character or NULL. A regular expression pattern to select a build log.
#' @param pipeline_dir Character. The path to the pipeline directory (used in error messages).
#'
#' @return Character. The selected build log filename.
#'
#' @keywords internal
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

#' Read and parse a JSON build log
#'
#' Parses a single build log JSON file into an R list structure.
#'
#' @param log_path Character. The path to the build log file.
#'
#' @return A list containing the parsed JSON contents.
#'
#' @keywords internal
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

#' Find a node's entry in a build log's nodes array
#'
#' Iterates through the list of nodes from a build log and returns the entry
#' matching the specified name.
#'
#' @param nodes A list of node entries from the build log.
#' @param name Character. The name of the node to find.
#' @param log_file Character. The filename of the log (used in error messages).
#'
#' @return A list representing the matched node entry.
#'
#' @keywords internal
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

#' Resolve an artifact path to an absolute path
#'
#' Converts a relative artifact path from the build log into an absolute path,
#' supporting both Unix and Windows absolute path styles.
#'
#' @param path Character. The raw artifact path.
#' @param pipeline_dir Character. The path to the pipeline directory.
#'
#' @return Character. The resolved absolute path.
#'
#' @keywords internal
resolve_artifact_path <- function(path, pipeline_dir) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("Node entry does not contain a valid artifact path.", call. = FALSE)
  }

  # Match Unix absolute paths (`/path/...`) and standard Windows drive-letter
  # absolute paths (`C:/path/...` or `C:\\path\\...`).
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
#' `_pipeline/` directory, locates the requested node, and deserializes the
#' node artifact. When `which_log` is `NULL`, the helper picks the first
#' reverse-alphabetically sorted `build_log_*.json` file, which matches T's
#' timestamped log naming and therefore resolves to the most recent build.
#'
#' @param name Name of the node to read.
#' @param which_log Optional regular expression used to select a specific build
#'   log filename. Defaults to the latest available build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to
#'   `"_pipeline"`.
#' @param deserializer Function used to deserialize the artifact file. Defaults
#'   to `readRDS()`.
#' @param return_path Logical. If `TRUE`, returns the path to the artifact
#'   instead of deserializing it. Defaults to `FALSE`.
#'
#' @return The deserialized node artifact, or the path to it if `return_path` is `TRUE`.
#'
#' @details
#' The function locates the pipeline folder and reads the selected build log. If
#' `return_path` is set to `TRUE`, it returns the absolute system path to the
#' serialized artifact instead of deserializing the object. Otherwise, it utilizes
#' the `deserializer` function to deserialize the R object.
#'
#' @examples
#' \init{
#'   # Assuming node "clean_data" was built successfully
#'   df <- read_node("clean_data")
#' }
#'
#' @export
read_node <- function(
    name,
    which_log = NULL,
    pipeline_dir = "_pipeline",
    deserializer = readRDS,
    return_path = FALSE) {
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

  if (isTRUE(return_path)) {
    return(artifact_path)
  }

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

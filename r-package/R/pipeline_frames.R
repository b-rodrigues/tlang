#' Load ordered names, entries, and deps map for frame helpers
#'
#' Uses the selected build log when logs exist, else the static DAG file.
#'
#' @param pipeline_dir Character. Pipeline directory.
#' @param which_log Character or NULL. Log selection regex.
#' @param dag_file Character. DAG filename when no logs exist.
#'
#' @return List with `names`, `entries`, and `deps_map`.
#'
#' @keywords internal
load_frame_data <- function(pipeline_dir, which_log, dag_file) {
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
    deps_map <- build_log_deps_map(nodes)
    entries <- list()
    for (entry in nodes) {
      if (is.list(entry) && !is.null(entry$node)) {
        entries[[as.character(entry$node)[[1L]]]] <- entry
      }
    }
    nm_vec <- names(deps_map)
    if (is.null(nm_vec)) nm_vec <- character(0)
    return(list(names = nm_vec, entries = entries, deps_map = deps_map))
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
  deps_map <- list()
  for (entry in normalized) {
    deps_map[[entry$node_name]] <- entry$depends
  }
  nm_vec <- names(deps_map)
  if (is.null(nm_vec)) nm_vec <- character(0)
  list(names = nm_vec, entries = list(), deps_map = deps_map)
}

#' Derive command vs script from build-log source fields
#'
#' @param entry List or NULL. One build-log node entry.
#'
#' @return Character scalar or NA.
#'
#' @keywords internal
command_type_of <- function(entry) {
  if (!is.list(entry)) {
    return(NA_character_)
  }
  script <- entry[["script"]]
  if (is.character(script) && length(script) == 1L && !is.na(script) && nzchar(trimws(script))) {
    return("script")
  }
  source <- entry[["source"]]
  if (is.character(source) && length(source) == 1L && !is.na(source) && nzchar(trimws(source))) {
    return("command")
  }
  NA_character_
}

#' Static per-node config table
#'
#' Mirrors T `pipeline_to_frame()`. One row per node with `name`,
#' `runtime`, `serializer`, `deserializer`, `noop`, `deps`, `depth`,
#' and `command_type`.
#'
#' File-based limits (explicit, not silent): build logs do not store
#' `deserializer` or `noop`, so both are always `NA`. `runtime` and
#' `serializer` are `NA` for unbuilt nodes from `dag.json`.
#' `command_type` is `"script"` when the log entry has a `script` field,
#' `"command"` when it has `source`, else `NA`. `deps` is a list column
#' (T uses a comma-separated string).
#'
#' @param pipeline_dir Path to the pipeline build directory.
#' @param which_log Optional regex to select a build log.
#' @param dag_file DAG filename used only when no build logs exist.
#'
#' @return A data frame with one row per node.
#'
#' @examples
#' \dontrun{
#'   tbl <- pipeline_to_frame()
#'   print(tbl)
#' }
#'
#' @export
pipeline_to_frame <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json") {
  validate_scalar_string(pipeline_dir, "pipeline_dir")
  data <- load_frame_data(pipeline_dir, which_log, dag_file)
  depths <- pipeline_node_depths(pipeline_dir = pipeline_dir, which_log = which_log, dag_file = dag_file)

  n <- length(data$names)
  runtime <- character(n)
  serializer <- character(n)
  command_type <- character(n)
  deps <- vector("list", n)
  depth <- integer(n)
  for (i in seq_along(data$names)) {
    nm <- data$names[[i]]
    entry <- data$entries[[nm]]
    runtime[[i]] <- inspect_text_or_na(if (is.list(entry)) entry$runtime else NULL)
    serializer[[i]] <- inspect_text_or_na(if (is.list(entry)) entry$serializer else NULL)
    command_type[[i]] <- command_type_of(entry)
    deps[[i]] <- data$deps_map[[nm]]
    depth[[i]] <- if (nm %in% names(depths)) as.integer(depths[[nm]]) else 0L
  }

  data.frame(
    name = data$names,
    runtime = runtime,
    serializer = serializer,
    deserializer = NA_character_,
    noop = NA,
    deps = I(deps),
    depth = depth,
    command_type = command_type,
    stringsAsFactors = FALSE
  )
}

#' Per-node config plus provenance counts
#'
#' Mirrors T `pipeline_config_to_frame()`. Returns all T column names.
#' Only `name`, `runtime`, `depth`, `command_type`, `serializer`, and
#' `n_deps` come from files. Every provenance column (`prov_*`), `shell`,
#' `flake`, `deserializer`, `noop`, and every count except `n_deps` is
#' `NA` because build logs and `dag.json` do not store that data.
#' `NA` means unknown, not zero.
#'
#' @param pipeline_dir Path to the pipeline build directory.
#' @param which_log Optional regex to select a build log.
#' @param dag_file DAG filename used only when no build logs exist.
#'
#' @return A data frame with one row per node and config columns.
#'
#' @examples
#' \dontrun{
#'   tbl <- pipeline_config_to_frame()
#'   print(tbl)
#' }
#'
#' @export
pipeline_config_to_frame <- function(pipeline_dir = "_pipeline", which_log = NULL, dag_file = "dag.json") {
  validate_scalar_string(pipeline_dir, "pipeline_dir")
  data <- load_frame_data(pipeline_dir, which_log, dag_file)
  depths <- pipeline_node_depths(pipeline_dir = pipeline_dir, which_log = which_log, dag_file = dag_file)

  n <- length(data$names)
  runtime <- character(n)
  serializer <- character(n)
  command_type <- character(n)
  depth <- integer(n)
  n_deps <- integer(n)
  for (i in seq_along(data$names)) {
    nm <- data$names[[i]]
    entry <- data$entries[[nm]]
    runtime[[i]] <- inspect_text_or_na(if (is.list(entry)) entry$runtime else NULL)
    serializer[[i]] <- inspect_text_or_na(if (is.list(entry)) entry$serializer else NULL)
    command_type[[i]] <- command_type_of(entry)
    depth[[i]] <- if (nm %in% names(depths)) as.integer(depths[[nm]]) else 0L
    n_deps[[i]] <- length(data$deps_map[[nm]])
  }

  data.frame(
    name = data$names,
    runtime = runtime,
    depth = depth,
    command_type = command_type,
    serializer = serializer,
    deserializer = NA_character_,
    noop = NA,
    shell = NA_character_,
    flake = NA_character_,
    prov_serializer = NA_character_,
    prov_deserializer = NA_character_,
    prov_noop = NA_character_,
    prov_shell = NA_character_,
    prov_flake = NA_character_,
    n_deps = n_deps,
    n_deps_global = NA_integer_,
    n_deps_node = NA_integer_,
    n_funcs = NA_integer_,
    n_funcs_global = NA_integer_,
    n_funcs_node = NA_integer_,
    n_incs = NA_integer_,
    n_incs_global = NA_integer_,
    n_incs_node = NA_integer_,
    n_env_vars = NA_integer_,
    n_env_vars_global = NA_integer_,
    n_env_vars_node = NA_integer_,
    n_args = NA_integer_,
    n_args_global = NA_integer_,
    n_args_node = NA_integer_,
    n_shell_args = NA_integer_,
    n_shell_args_global = NA_integer_,
    n_shell_args_node = NA_integer_,
    stringsAsFactors = FALSE
  )
}

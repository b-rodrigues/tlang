#' Load diffobj lazily so basic package imports still work without it
#'
#' @return Namespace. The loaded diffobj namespace.
#'
#' @keywords internal
load_diffobj <- function() {
  if (!requireNamespace("diffobj", quietly = TRUE)) {
    stop(
      "diffobj is required for R object diffs. Install the `tlang` R package with its dependencies so `diff_nodes()` can compare R artifacts.",
      call. = FALSE
    )
  }

  asNamespace("diffobj")
}

#' Strip ANSI escape sequences from captured diff output
#'
#' @param lines Character vector.
#'
#' @return Character vector with ANSI escape sequences removed.
#'
#' @keywords internal
strip_ansi <- function(lines) {
  gsub("\033\\[[0-9;]*[[:alpha:]]", "", lines, perl = TRUE)
}

#' Return an object's dimensions as an integer vector when available
#'
#' @param obj Any R object.
#'
#' @return Integer vector or NULL.
#'
#' @keywords internal
shape_info <- function(obj) {
  dims <- dim(obj)
  if (is.null(dims)) {
    return(NULL)
  }

  as.integer(dims)
}

#' Choose the most informative value type label for the diff envelope
#'
#' @param obj_a First object.
#' @param obj_b Second object.
#' @param class_a Optional explicit class label for the first object.
#' @param class_b Optional explicit class label for the second object.
#'
#' @return Character scalar.
#'
#' @keywords internal
value_type <- function(obj_a, obj_b, class_a = NULL, class_b = NULL) {
  class_a <- if (is.character(class_a) && length(class_a) == 1L) trimws(class_a) else ""
  class_b <- if (is.character(class_b) && length(class_b) == 1L) trimws(class_b) else ""

  if (nzchar(class_a) && identical(class_a, class_b)) {
    return(class_a)
  }

  if (nzchar(class_a) && nzchar(class_b)) {
    return(sprintf("%s -> %s", class_a, class_b))
  }

  obj_class_a <- paste(class(obj_a), collapse = "/")
  obj_class_b <- paste(class(obj_b), collapse = "/")
  if (identical(obj_class_a, obj_class_b)) {
    obj_class_a
  } else {
    sprintf("%s -> %s", obj_class_a, obj_class_b)
  }
}

#' Capture a diffobj rendering for two R objects
#'
#' @param obj_a First object.
#' @param obj_b Second object.
#' @param context Integer. Requested diff context.
#'
#' @return Character vector of rendered diff lines.
#'
#' @keywords internal
render_diffobj <- function(obj_a, obj_b, context = 3L) {
  diffobj_ns <- load_diffobj()
  old_options <- options(
    crayon.enabled = FALSE,
    cli.num_colors = 1L
  )
  on.exit(options(old_options), add = TRUE)

  diff <- tryCatch(
    diffobj_ns$diffObj(obj_a, obj_b, context = as.integer(context)),
    error = function(err) {
      stop(
        sprintf("Failed to diff R objects with diffobj: %s", conditionMessage(err)),
        call. = FALSE
      )
    }
  )

  strip_ansi(capture.output(print(diff)))
}

#' Diff two R objects and return a T-compatible VDiff envelope
#'
#' @param obj_a First R object.
#' @param obj_b Second R object.
#' @param node_a Name of the first node.
#' @param node_b Name of the second node.
#' @param log_a Build selector for the first artifact.
#' @param log_b Build selector for the second artifact.
#' @param class_a Optional explicit class label for the first object.
#' @param class_b Optional explicit class label for the second object.
#' @param context Integer. Requested diff context.
#'
#' @return A list representing a `VDiff` envelope.
#'
#' @export
diff_objects <- function(
    obj_a,
    obj_b,
    node_a = "node_a",
    node_b = "node_b",
    log_a = "latest",
    log_b = "latest",
    class_a = NULL,
    class_b = NULL,
    context = 3L) {
  identical_objects <- identical(obj_a, obj_b)
  detail <- list()
  detailed_summary <- "Objects are identical."

  if (!identical_objects) {
    diff_lines <- render_diffobj(obj_a, obj_b, context = context)
    detail <- list(
      renderer = "diffobj",
      lines = unname(diff_lines)
    )
    detailed_summary <- paste(diff_lines, collapse = "\n")
  }

  summary <- list(
    changes = if (identical_objects) 0L else length(detail$lines),
    class_a = unname(class(obj_a)),
    class_b = unname(class(obj_b)),
    typeof_a = typeof(obj_a),
    typeof_b = typeof(obj_b),
    length_a = length(obj_a),
    length_b = length(obj_b)
  )

  shape_a <- shape_info(obj_a)
  shape_b <- shape_info(obj_b)
  if (!is.null(shape_a)) {
    summary$shape_a <- shape_a
  }
  if (!is.null(shape_b)) {
    summary$shape_b <- shape_b
  }

  list(
    kind = "r_object_diff",
    node_a = node_a,
    node_b = node_b,
    log_a = log_a,
    log_b = log_b,
    value_type = value_type(obj_a, obj_b, class_a = class_a, class_b = class_b),
    identical = identical_objects,
    summary = summary,
    detail = detail,
    detailed_summary = detailed_summary,
    hunks = list()
  )
}

#' Deserialize two artifacts and diff the resulting R objects
#'
#' @param path_a Path to the first artifact.
#' @param path_b Path to the second artifact.
#' @param node_a Name of the first node.
#' @param node_b Name of the second node.
#' @param log_a Build selector for the first artifact.
#' @param log_b Build selector for the second artifact.
#' @param class_a Optional explicit class label for the first object.
#' @param class_b Optional explicit class label for the second object.
#' @param context Integer. Requested diff context.
#' @param deserializer Function used to deserialize the artifact file. Defaults to `readRDS()`.
#'
#' @return A list representing a `VDiff` envelope.
#'
#' @export
diff_artifacts <- function(
    path_a,
    path_b,
    node_a = "node_a",
    node_b = "node_b",
    log_a = "latest",
    log_b = "latest",
    class_a = NULL,
    class_b = NULL,
    context = 3L,
    deserializer = readRDS) {
  if (!is.function(deserializer)) {
    stop("`deserializer` must be a function.", call. = FALSE)
  }

  obj_a <- deserializer(path_a)
  obj_b <- deserializer(path_b)

  diff_objects(
    obj_a,
    obj_b,
    node_a = node_a,
    node_b = node_b,
    log_a = log_a,
    log_b = log_b,
    class_a = class_a,
    class_b = class_b,
    context = context
  )
}

#' Load two nodes via `read_node()` and diff their deserialized R objects
#'
#' @param node_a Name of the first node.
#' @param node_b Name of the second node.
#' @param which_log_a Optional regular expression used to select the first build log.
#' @param which_log_b Optional regular expression used to select the second build log.
#' @param pipeline_dir Path to the pipeline build directory. Defaults to `"_pipeline"`.
#' @param context Integer. Requested diff context.
#'
#' @return A list representing a `VDiff` envelope.
#'
#' @export
diff_nodes <- function(
    node_a,
    node_b,
    which_log_a = NULL,
    which_log_b = NULL,
    pipeline_dir = "_pipeline",
    context = 3L) {
  path_a <- read_node(node_a, which_log = which_log_a, pipeline_dir = pipeline_dir, return_path = TRUE)
  path_b <- read_node(node_b, which_log = which_log_b, pipeline_dir = pipeline_dir, return_path = TRUE)

  diff_artifacts(
    path_a,
    path_b,
    node_a = node_a,
    node_b = node_b,
    log_a = if (is.null(which_log_a)) "latest" else which_log_a,
    log_b = if (is.null(which_log_b)) "latest" else which_log_b,
    context = context
  )
}

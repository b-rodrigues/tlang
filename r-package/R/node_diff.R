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
#' @return List with ANSI-preserving and ANSI-stripped rendered diff lines.
#'
#' @keywords internal
render_diffobj <- function(obj_a, obj_b, context = 3L) {
  diffobj_ns <- load_diffobj()
  old_options <- options(
    crayon.enabled = TRUE,
    cli.num_colors = 256L
  )
  on.exit(options(old_options), add = TRUE)

  diff <- tryCatch(
    diffobj_ns$diffObj(
      obj_a,
      obj_b,
      context = as.integer(context),
      mode = "unified"
    ),
    error = function(err) {
      stop(
        sprintf("Failed to diff R objects with diffobj: %s", conditionMessage(err)),
        call. = FALSE
      )
    }
  )

  raw_lines <- unname(capture.output(print(diff)))
  list(
    raw_lines = raw_lines,
    clean_lines = unname(strip_ansi(raw_lines))
  )
}

#' Convert rendered diffobj lines to coarse VDiff hunks
#'
#' @param lines ANSI-stripped rendered diff lines.
#'
#' @return List of hunk dictionaries compatible with the T VDiff envelope.
#'
#' @keywords internal
diffobj_hunks <- function(lines) {
  if (!length(lines)) {
    return(list())
  }

  header_matches <- gregexpr("^@@ -[0-9]+(?:,[0-9]+)? \\+[0-9]+(?:,[0-9]+)? @@", lines, perl = TRUE)
  header_idx <- which(vapply(header_matches, function(hit) hit[1] > 0L, logical(1)))

  parse_hunk <- function(block) {
    header <- block[[1]]
    captures <- regmatches(
      header,
      regexec("^@@ -([0-9]+)(?:,([0-9]+))? \\+([0-9]+)(?:,([0-9]+))? @@", header, perl = TRUE)
    )[[1]]
    a_start <- as.integer(captures[[2]]) - 1L
    a_len <- if (!is.na(captures[[3]]) && nzchar(captures[[3]])) as.integer(captures[[3]]) else 1L
    b_start <- as.integer(captures[[4]]) - 1L
    b_len <- if (!is.na(captures[[5]]) && nzchar(captures[[5]])) as.integer(captures[[5]]) else 1L

    lines_a <- character()
    lines_b <- character()
    has_prev <- FALSE
    has_next <- FALSE

    if (length(block) > 1L) {
      for (line in block[-1]) {
        if (grepl("^-", line)) {
          has_prev <- TRUE
          lines_a <- c(lines_a, sub("^-\\s?", "", line))
        } else if (grepl("^\\+", line)) {
          has_next <- TRUE
          lines_b <- c(lines_b, sub("^\\+\\s?", "", line))
        } else if (grepl("^ ", line)) {
          shared <- sub("^\\s+", "", line)
          lines_a <- c(lines_a, shared)
          lines_b <- c(lines_b, shared)
        } else {
          shared <- line
          lines_a <- c(lines_a, shared)
          lines_b <- c(lines_b, shared)
        }
      }
    }

    kind <- if (has_prev && has_next) {
      "replace"
    } else if (has_prev) {
      "delete"
    } else if (has_next) {
      "insert"
    } else {
      "equal"
    }

    list(
      kind = kind,
      a_start = a_start,
      a_end = a_start + a_len,
      b_start = b_start,
      b_end = b_start + b_len,
      lines_a = as.list(unname(lines_a)),
      lines_b = as.list(unname(lines_b))
    )
  }

  if (!length(header_idx)) {
    return(list(
      list(
        kind = "replace",
        a_start = 0L,
        a_end = length(lines),
        b_start = 0L,
        b_end = length(lines),
        lines_a = as.list(unname(lines)),
        lines_b = as.list(unname(lines))
      )
    ))
  }

  starts <- header_idx
  ends <- c(header_idx[-1] - 1L, length(lines))
  Map(function(start, end) parse_hunk(lines[start:end]), starts, ends)
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
  hunks <- list()

  if (!identical_objects) {
    rendered <- render_diffobj(obj_a, obj_b, context = context)
    detail <- list(
      renderer = "diffobj",
      lines = rendered$clean_lines
    )
    detailed_summary <- paste(rendered$raw_lines, collapse = "\n")
    hunks <- diffobj_hunks(rendered$clean_lines)
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
    hunks = hunks
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

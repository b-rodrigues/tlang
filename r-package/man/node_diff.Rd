\name{diff_objects}
\alias{diff_objects}
\alias{diff_artifacts}
\alias{diff_nodes}
\title{Diff R node artifacts from built T pipelines}
\usage{
diff_objects(
  obj_a,
  obj_b,
  node_a = "node_a",
  node_b = "node_b",
  log_a = "latest",
  log_b = "latest",
  class_a = NULL,
  class_b = NULL,
  context = 3L
)

diff_artifacts(
  path_a,
  path_b,
  node_a = "node_a",
  node_b = "node_b",
  log_a = "latest",
  log_b = "latest",
  class_a = NULL,
  class_b = NULL,
  context = 3L,
  deserializer = readRDS
)

diff_nodes(
  node_a,
  node_b,
  which_log_a = NULL,
  which_log_b = NULL,
  pipeline_dir = "_pipeline",
  context = 3L
)
}
\arguments{
  \item{obj_a}{First R object.}

  \item{obj_b}{Second R object.}

  \item{path_a}{Path to the first artifact.}

  \item{path_b}{Path to the second artifact.}

  \item{node_a}{Name of the first node.}

  \item{node_b}{Name of the second node.}

  \item{log_a}{Build selector for the first artifact.}

  \item{log_b}{Build selector for the second artifact.}

  \item{class_a}{Optional explicit class label for the first object.}

  \item{class_b}{Optional explicit class label for the second object.}

  \item{context}{Integer. Requested diff context.}

  \item{deserializer}{Function used to deserialize the artifact file. Defaults to \code{readRDS}.}

  \item{which_log_a}{Optional regular expression used to select the first build log.}

  \item{which_log_b}{Optional regular expression used to select the second build log.}

  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to \code{"_pipeline"}.}
}
\value{
A list representing a \code{VDiff} envelope.
}
\description{
Diffs two in-memory R objects, two artifact files, or two pipeline nodes using
\pkg{diffobj} and returns a structured result compatible with T's node diff
envelope.
}
\examples{
\dontrun{
diff_objects(list(a = 1), list(a = 2))
diff_artifacts("old.rds", "new.rds")
diff_nodes("model", "model", which_log_a = "20260501", which_log_b = "latest")
}
}

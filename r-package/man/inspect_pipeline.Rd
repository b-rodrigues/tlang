\name{inspect_pipeline}
\alias{inspect_pipeline}
\title{Inspect pipeline nodes and their latest build status}
\usage{
inspect_pipeline(
  pipeline_dir = "_pipeline",
  which_log = NULL,
  dag_file = "dag.json"
)
}
\arguments{
  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}

  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}

  \item{dag_file}{Name of the DAG JSON file used only when no build logs
  exist. Defaults to \code{"dag.json"}.}
}
\value{
A data frame with columns \code{node}, \code{runtime}, \code{serializer},
\code{depends} (list of character vectors), \code{status}, \code{class}, and
\code{path}. Falls back to the static DAG with \code{status} set to
\code{"unbuilt"} when no build logs exist.
}
\description{
Reads the selected build log and returns one row per node with its runtime,
serializer, dependencies, status, class, and resolved artifact path.
}
\examples{
\dontrun{
tbl <- inspect_pipeline()
print(tbl)
}
}

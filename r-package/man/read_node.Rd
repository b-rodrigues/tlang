\name{read_node}
\alias{read_node}
\title{Read a node artifact from a built T pipeline}
\usage{
read_node(
  name,
  which_log = NULL,
  pipeline_dir = "_pipeline",
  deserializer = readRDS
)
}
\arguments{
  \item{name}{Name of the node to read.}

  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}

  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}

  \item{deserializer}{Function used to deserialize the artifact file. Defaults
  to \code{readRDS}.}
}
\value{
The deserialized node artifact.
}
\description{
Reads the latest build log, or a matching historical one, from the
\code{_pipeline/} directory, locates the requested node, and deserializes its
artifact. When \code{which_log} is \code{NULL}, the helper picks the first
reverse-alphabetically sorted \code{build_log_*.json} file, which matches T's
timestamped log naming and therefore resolves to the most recent build.
}
\examples{
\dontrun{
read_node("model")
read_node("features", deserializer = arrow::read_ipc_file)
read_node("model", which_log = "20260221")
}
}

\name{read_node}
\alias{read_node}
\title{Read a node artifact from a built T pipeline}
\usage{
read_node(
  name,
  which_log = NULL,
  pipeline_dir = "_pipeline",
  deserializer = NULL,
  return_path = FALSE
)
}
\arguments{
  \item{name}{Name of the node to read.}

  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}

  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}

  \item{deserializer}{Function or \code{NULL}. When \code{NULL} (the default),
  the \code{serializer} field from the build log picks the reader
  automatically (\code{readRDS} for \code{default}, \code{jsonlite::read_json}
  for \code{^json}, \code{read.csv} for \code{^csv},
  \code{arrow::read_ipc_file} for \code{^ipc}, \code{arrow::read_parquet} for
  \code{^parquet}). Pass a function to override.}

  \item{return_path}{Logical. If \code{TRUE}, return the artifact path instead
  of deserializing it.}
}
\value{
The deserialized node artifact, or the path when \code{return_path} is \code{TRUE}.
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
read_node("features")
read_node("features", deserializer = arrow::read_ipc_file)
read_node("model", which_log = "20260221")
}
}

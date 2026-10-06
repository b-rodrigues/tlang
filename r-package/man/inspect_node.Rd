\name{inspect_node}
\alias{inspect_node}
\title{Inspect one node's metadata, lineage, error, and warnings}
\usage{
inspect_node(name, which_log = NULL, pipeline_dir = "_pipeline")
}
\arguments{
  \item{name}{Name of the node to inspect.}

  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}

  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}
}
\value{
A named list with \code{name}, \code{runtime}, \code{serializer},
\code{dependencies}, \code{children} (direct dependents), \code{status},
\code{class}, \code{path}, \code{error} (\code{code}/\code{message} record or
\code{NULL}), and \code{warnings}.
}
\description{
Inspects a single node from the selected build log without loading its
artifact value.
}
\examples{
\dontrun{
info <- inspect_node("model")
print(info$runtime)
}
}

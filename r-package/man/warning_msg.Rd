\name{warning_msg}
\alias{warning_msg}
\title{Get a node's formatted warnings}
\usage{
warning_msg(name, which_log = NULL, pipeline_dir = "_pipeline")
}
\arguments{
  \item{name}{Name of the node to inspect.}

  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}

  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}
}
\value{
The formatted warning message, or \code{""} when there are none.
}
\description{
Upstream warnings are prefixed with the source node name, and multiple
warnings join with \code{". Furthermore, "}. Mirrors T's
\code{warning_msg()}.
}
\examples{
\dontrun{
msg <- warning_msg("model")
print(msg)
}
}

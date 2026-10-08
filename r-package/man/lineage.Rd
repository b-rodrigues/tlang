\name{lineage}
\alias{lineage}
\title{List a node's transitive parents and children}
\usage{
lineage(name, which_log = NULL, pipeline_dir = "_pipeline", direction = "both")
}
\arguments{
  \item{name}{Name of the node.}

  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}

  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}

  \item{direction}{One of \code{"parents"}, \code{"children"}, or
  \code{"both"} (the default).}
}
\value{
A named list with \code{parents} (nearest first) and \code{children}
(nearest first).
}
\description{
Lists transitive dependency and dependent names from the single selected
build log, without loading artifact values.
}
\examples{
\dontrun{
lin <- lineage("model")
print(lin$parents)
}
}

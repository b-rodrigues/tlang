\name{build_log_to_frame}
\alias{build_log_to_frame}
\title{Tabulate one build log as per-node rows}
\usage{
build_log_to_frame(which_log = NULL, pipeline_dir = "_pipeline")
}
\arguments{
  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}

  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}
}
\value{
A data frame with columns \code{name}, \code{status}, \code{duration}, and
\code{path}.
}
\description{
Tabulates the selected build log, one row per node. Mirrors T's
\code{build_log_to_frame()}.
}
\examples{
\dontrun{
tbl <- build_log_to_frame()
print(tbl)
}
}

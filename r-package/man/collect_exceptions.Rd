\name{collect_exceptions}
\alias{collect_exceptions}
\title{Gather error and warning rows from one build log}
\usage{
collect_exceptions(pipeline_dir = "_pipeline", which_log = NULL)
}
\arguments{
  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}

  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}
}
\value{
A data frame with columns \code{node}, \code{status} (\code{Error}/
\code{Warning}), \code{code}, and \code{message}.
}
\description{
Collects error rows from \code{Errored} and soft-failed nodes plus warning
rows from per-artifact \code{warnings} sidecars. Mirrors T's
\code{collect_exceptions()}.
}
\examples{
\dontrun{
errs <- collect_exceptions()
print(errs)
}
}

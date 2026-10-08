\name{error_msg}
\alias{error_msg}
\alias{error_code}
\alias{error_context}
\title{Read a failed node's error}
\usage{
error_msg(name, which_log = NULL, pipeline_dir = "_pipeline")
error_code(name, which_log = NULL, pipeline_dir = "_pipeline")
error_context(name, which_log = NULL, pipeline_dir = "_pipeline")
}
\arguments{
  \item{name}{Name of the node to inspect.}

  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}

  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}
}
\value{
\code{error_msg} returns the message string, \code{error_code} the code
string, and \code{error_context} the context list. All three stop when the
node has no error, mirroring T.
}
\description{
Foreign-runtime failures are stored as VError JSON, so an R error message
reads the same from R, Python, or Julia.
}
\examples{
\dontrun{
msg <- error_msg("model")
print(msg)
}
}

\name{list_logs}
\alias{list_logs}
\title{List build logs in the pipeline directory}
\usage{
list_logs(pipeline_dir = "_pipeline")
}
\arguments{
  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}
}
\value{
A data frame with columns \code{filename}, \code{modification_time},
\code{size_kb}, and \code{pipeline}, newest first.
}
\description{
Lists every \code{build_log_*.json} file with its local modification time,
size, and logged pipeline name. Mirrors T's \code{list_logs()}.
}
\examples{
\dontrun{
logs <- list_logs()
print(logs)
}
}

\name{show_code}
\alias{show_code}
\title{Get a node's source code for copy-paste tweaking}
\usage{
show_code(name, which_log = NULL, pipeline_dir = "_pipeline", verify = FALSE)
}
\arguments{
  \item{name}{Name of the node to inspect.}

  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}

  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}

  \item{verify}{Logical. Verify a script file against its recorded hash.
  Defaults to \code{FALSE}.}
}
\value{
Character. The node source code, or the script path for exterior scripts.
}
\description{
Foreign code comes back verbatim; T expressions come back as normalized T
source. Nodes built from an exterior \code{script =} file return the script
path instead (no copy is stored). Older build logs without recorded source
raise an error telling you to rebuild.
}
\examples{
\dontrun{
cat(show_code("model"))
}
}

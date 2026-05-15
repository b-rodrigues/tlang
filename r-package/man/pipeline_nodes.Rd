\name{pipeline_nodes}
\alias{pipeline_nodes}
\title{List pipeline nodes from _pipeline/dag.json in a tree-like view}
\usage{
pipeline_nodes(pipeline_dir = "_pipeline", dag_file = "dag.json")
}
\arguments{
  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}

  \item{dag_file}{Name of the DAG JSON file inside \code{pipeline_dir}.
  Defaults to \code{"dag.json"}.}
}
\value{
Character vector with one line per rendered tree node.
}
\description{
Reads a pipeline DAG definition from \code{_pipeline/dag.json} and returns a
character vector representing the pipeline structure as an ASCII tree.
}
\examples{
\dontrun{
cat(pipeline_nodes(), sep = "\n")
}
}

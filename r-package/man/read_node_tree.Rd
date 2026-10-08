\name{read_node_tree}
\alias{read_node_tree}
\title{Read a node and all of its related nodes}
\usage{
read_node_tree(
  name,
  which_log = NULL,
  pipeline_dir = "_pipeline",
  deserializer = NULL,
  return_path = FALSE,
  include = "children",
  on_unreadable = "error"
)
}
\arguments{
  \item{name}{Name of the root node to read.}

  \item{which_log}{Optional regular expression used to select a specific build
  log filename. Defaults to the latest available build log.}

  \item{pipeline_dir}{Path to the pipeline build directory. Defaults to
  \code{"_pipeline"}.}

  \item{deserializer}{Function or \code{NULL}. When \code{NULL} (the default),
  each node picks its reader from its own build-log \code{serializer} field.}

  \item{return_path}{Logical. Return artifact paths instead of values.}

  \item{include}{One of \code{"children"} (nodes that depend on \code{name}),
  \code{"parents"} (nodes \code{name} depends on), or \code{"both"}.}

  \item{on_unreadable}{One of \code{"error"} (abort the tree), \code{"path"}
  (fall back to a \code{list(path, serializer)} record), or \code{"skip"} (omit the node).}
}
\value{
A named list mapping node name to deserialized value. With
\code{on_unreadable = "path"}, an unreadable node maps to a
\code{list(path, serializer)} record holding the artifact path and the
build-log serializer, so the caller can recover manually.
}
\description{
Reads the requested node plus its transitive children, parents, or both, using
the build-log \code{dependencies} arrays for graph traversal. Each node uses
its own recorded serializer unless \code{deserializer} overrides it. All nodes
come from the single selected build log.
}
\examples{
\dontrun{
tree <- read_node_tree("clean_data")
tree <- read_node_tree("clean_data", include = "both")
tree <- read_node_tree("clean_data", on_unreadable = "path")
}
}

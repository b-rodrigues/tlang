# tlang Julia package

This companion Julia package provides a Julia `read_node()` helper for reading
artifacts from built T pipelines.

## Installation

From the Julia REPL:

```julia
using Pkg
Pkg.develop(path="jl-package")
```

## Usage

By default, `read_node()` uses Julia's native `Serialization.deserialize`:

```julia
using tlang

model = read_node("model")
```

Pass a custom deserializer when a node uses another artifact format (e.g., CSV):

```julia
using tlang, DataFrames, CSV

table = read_node("features", deserializer = p -> CSV.read(p, DataFrame))
```

You can also target a specific historical build log:

```julia
older_model = read_node("model", which_log = "20260221")
```

## Inspect pipeline DAG

Get the nodes and their dependencies as a `Dict`:

```julia
using tlang

nodes = pipeline_nodes()
println(nodes)
```

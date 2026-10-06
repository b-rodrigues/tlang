module tlang

using JSON
using Serialization

export read_node, read_node_tree, inspect_pipeline, inspect_node, lineage, error_msg, error_code, error_context, warning_msg, list_logs, build_log_to_frame, collect_exceptions, pipeline_nodes, diff_artifacts, diff_nodes, diff_objects

const FIXTURE_LOGS = ["build_log_ocaml_mock.json", "build_log_legacy_version.json"]

"""
    _list_build_logs(pipeline_dir::String)

List build log JSON files in the pipeline directory, sorted reverse-alphabetically.

Filters out internal fixture logs when running within the repository checkout.

# Arguments
- `pipeline_dir::String`: The path to the pipeline directory containing the build logs.

# Returns
- `Vector{String}`: A sorted list of build log filenames.
"""
function _list_build_logs(pipeline_dir::String)
    logs = filter(f -> startswith(f, "build_log_") && endswith(f, ".json"), readdir(pipeline_dir))
    sort!(logs, rev=true)
    
    # Mirror T's fixture-log filtering only when reading from a repository
    # checkout, where these internal fixture logs can live beside real build logs.
    builder_logs_ml_path = joinpath(dirname(pipeline_dir), "src", "pipeline", "builder_logs.ml")
    if isfile(builder_logs_ml_path) && length(logs) > 1 && any(l -> !(l in FIXTURE_LOGS), logs)
        logs = filter(l -> !(l in FIXTURE_LOGS), logs)
    end
    
    return logs
end

"""
    _select_build_log(logs::Vector{String}, which_log::Union{String, Nothing}, pipeline_dir::String)

Select a build log file from the list based on the provided regex pattern or defaults to the latest.

# Arguments
- `logs::Vector{String}`: A list of available build log filenames.
- `which_log::Union{String, Nothing}`: An optional regex pattern string to select a log.
  If `nothing`, the latest (first in the sorted list) log file is selected.
- `pipeline_dir::String`: The path to the pipeline directory (used in error reporting).

# Returns
- `String`: The selected build log filename.

# Throws
- `ErrorException`: If no build logs are found, or if `which_log` regex is invalid, or if no logs match the pattern.
"""
function _select_build_log(logs::Vector{String}, which_log::Union{String, Nothing}, pipeline_dir::String)
    if isnothing(which_log)
        if isempty(logs)
            error("No build logs found in `$pipeline_dir`. Build the pipeline first.")
        end
        return logs[1]
    end
    
    pattern =
        try
            Regex(which_log)
        catch e
            error("Invalid `which_log` regex pattern \"$which_log\": $e")
        end
    matches = filter(l -> occursin(pattern, l), logs)
    
    if isempty(matches)
        error("No build logs found in `$pipeline_dir` matching \"$which_log\".")
    end
    
    return matches[1]
end

"""
    _find_node_entry(nodes::Vector{Any}, name::String, log_file::String)

Locate the build log entry for a specific node name.

# Arguments
- `nodes::Vector{Any}`: The `nodes` array/list parsed from the build log JSON.
- `name::String`: The name of the node to find.
- `log_file::String`: The name of the build log file (used in error reporting).

# Returns
- `AbstractDict`: The dictionary containing the node configuration and metadata.

# Throws
- `ErrorException`: If the node name cannot be found in the nodes list.
"""
function _find_node_entry(nodes::Vector{Any}, name::String, log_file::String)
    for entry in nodes
        if entry isa AbstractDict && get(entry, "node", nothing) == name
            return entry
        end
    end
    error("Node `$name` not found in build log `$log_file`.")
end

"""
    _validate_node_entry(entry::Any, index::Int, dag_path::String)

Validate a single entry from the DAG configuration.

# Arguments
- `entry::Any`: The raw entry object, expected to be a dictionary.
- `index::Int`: The 1-based index of the entry in the DAG file (used in error reporting).
- `dag_path::String`: The path to the DAG file (used in error reporting).

# Returns
- `Tuple{String, Vector{String}}`: A tuple containing the node name and its sorted, unique dependencies.

# Throws
- `ErrorException`: If the entry is not a dictionary, if `node_name` is invalid, or if `depends` is invalid.
"""
function _validate_node_entry(entry::Any, index::Int, dag_path::String)
    if !(entry isa AbstractDict)
        error("Entry $index in `$dag_path` must be an object.")
    end

    node_name = get(entry, "node_name", nothing)
    depends = get(entry, "depends", String[])
    if isnothing(depends)
        depends = String[]
    end

    if !(node_name isa String) || isempty(strip(node_name))
        error("Entry $index in `$dag_path` has an invalid `node_name`.")
    end

    if !(depends isa Vector)
        error("Node `$node_name` in `$dag_path` has an invalid `depends` list.")
    end

    dep_names = String[]
    for dep in depends
        if !(dep isa String) || isempty(strip(dep))
            error("Node `$node_name` in `$dag_path` has an invalid `depends` list.")
        end
        push!(dep_names, dep)
    end

    return node_name, unique(sort(dep_names))
end

"""
    pipeline_nodes(; pipeline_dir::String="_pipeline", dag_file::String="dag.json")

Get pipeline nodes and their dependencies from the DAG configuration.

Reads and validates the DAG definition from a JSON file (typically `_pipeline/dag.json`)
and returns a dictionary mapping node names to their lists of dependencies.

# Keywords
- `pipeline_dir::String`: The path to the pipeline directory where the DAG file is located.
  Defaults to `"_pipeline"`.
- `dag_file::String`: The filename of the DAG configuration. Defaults to `"dag.json"`.

# Returns
- `Dict{String, Vector{String}}`: A dictionary mapping node names to their sorted, unique dependencies.

# Throws
- `ErrorException`: If the pipeline directory or DAG file does not exist, if the JSON structure is malformed,
  contains duplicate node names, or references unknown dependencies.
"""
function pipeline_nodes(; pipeline_dir::String="_pipeline", dag_file::String="dag.json")
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end

    dag_path = joinpath(pipeline_dir, dag_file)
    if !isfile(dag_path)
        error("DAG file `$dag_path` does not exist.")
    end

    dag = try
        JSON.parsefile(dag_path)
    catch e
        error("Failed to read DAG file `$dag_path`: $e")
    end

    if !(dag isa Vector)
        error("DAG file `$dag_path` must decode to an array.")
    end

    normalized = [_validate_node_entry(entry, idx, dag_path) for (idx, entry) in enumerate(dag)]
    node_names = [name for (name, _) in normalized]

    duplicate_names = unique([name for name in node_names if count(==(name), node_names) > 1])
    if !isempty(duplicate_names)
        error("DAG file `$dag_path` has duplicate node_name values: $(join(sort(duplicate_names), ", "))")
    end

    unknown_deps = String[]
    for (_, deps) in normalized
        for dep in deps
            if !(dep in node_names) && !(dep in unknown_deps)
                push!(unknown_deps, dep)
            end
        end
    end
    if !isempty(unknown_deps)
        error("DAG file `$dag_path` references unknown dependencies: $(join(sort(unknown_deps), ", "))")
    end

    return Dict(normalized)
end

"""
    _resolve_artifact_path(path_val::String, pipeline_dir::String)

Resolve an artifact path from a build log to an absolute file system path.

# Arguments
- `path_val::String`: The relative or absolute path value to resolve.
- `pipeline_dir::String`: The path to the pipeline directory.

# Returns
- `String`: The resolved absolute path to the artifact.
"""
function _resolve_artifact_path(path_val::String, pipeline_dir::String)
    if isabspath(path_val)
        return path_val
    end
    # The artifact path in the log is relative to the project root (parent of _pipeline)
    return abspath(joinpath(dirname(abspath(pipeline_dir)), path_val))
end

"""
    _normalize_serializer(serializer::String)

Strip a leading `^`, trim whitespace, and lowercase so `"^JSON"` maps to
`"json"`. Empty values map to `"default"`.
"""
function _normalize_serializer(serializer::String)
    s = lowercase(strip(serializer))
    while startswith(s, "^")
        s = s[2:end]
    end
    return isempty(strip(s)) ? "default" : s
end

"""
    _auto_deserializer(serializer::String, artifact_path::String)

Pick a deserializer based on the serializer name recorded in the build log.

Supported mappings (each names its Julia package when missing):
- `default`/`tlang`/`tobj`/`serialize` → `Serialization.deserialize`
- `json` → `JSON.parsefile` (`JSON` ships with the package)
- `csv` → `CSV.read(path, DataFrame)` (requires `using CSV, DataFrames`)
- `ipc`/`arrow` → `Arrow.Table(path) |> DataFrame` (requires `using Arrow, DataFrames`)
- `parquet` → `DataFrame(Parquet2.readfile(path))` (requires `using Parquet2, DataFrames`)
- `text`/`txt` → `read(path, String)` (stdlib, verbatim bytes as text)
- `pmml`/`onnx`/`bin`/unknown → explicit error suggesting `return_path=true`
  or a custom `deserializer`.

`^json` returns plain dicts and lists. `^text` returns file contents verbatim
(bytes decoded as UTF-8), matching Python and R.
"""
function _auto_deserializer(serializer::String, artifact_path::String)
    s = _normalize_serializer(serializer)
    if s in ("default", "tlang", "tobj", "serialize")
        return Serialization.deserialize(artifact_path)
    elseif s == "json"
        return JSON.parsefile(artifact_path)
    elseif s == "csv"
        # Try CSV.jl + DataFrames.jl; give a clear message if they are not loaded.
        if !isdefined(Main, :CSV) || !isdefined(Main, :DataFrames)
            error(
                "Node artifact uses serializer `^csv` but `CSV` and `DataFrames` are not loaded. " *
                "Run `using CSV, DataFrames` first (declare `CSV`, `DataFrames` in `tproject.toml`, run `t update`, re-enter `nix develop`), then call read_node() again. " *
                "Or pass `deserializer = p -> CSV.read(p, DataFrame)`."
            )
        end
        csv_mod = getfield(Main, :CSV)
        df_mod  = getfield(Main, :DataFrames)
        return Base.invokelatest(getfield(csv_mod, :read), artifact_path, getfield(df_mod, :DataFrame))
    elseif s in ("ipc", "arrow")
        if !isdefined(Main, :Arrow) || !isdefined(Main, :DataFrames)
            error(
                "Node artifact uses serializer `^ipc` but `Arrow` and `DataFrames` are not loaded. " *
                "Run `using Arrow, DataFrames` first (declare `Arrow`, `DataFrames` in `tproject.toml`, run `t update`, re-enter `nix develop`), then call read_node() again."
            )
        end
        arrow_mod = getfield(Main, :Arrow)
        df_mod = getfield(Main, :DataFrames)
        tbl = Base.invokelatest(getfield(arrow_mod, :Table), artifact_path)
        return Base.invokelatest(getfield(df_mod, :DataFrame), tbl)
    elseif s == "parquet"
        if !isdefined(Main, :Parquet2) || !isdefined(Main, :DataFrames)
            error(
                "Node artifact uses serializer `^parquet` but `Parquet2` and `DataFrames` are not loaded. " *
                "Run `using Parquet2, DataFrames` first (declare `Parquet2`, `DataFrames` in `tproject.toml`, run `t update`, re-enter `nix develop`), then call read_node() again."
            )
        end
        pq_mod = getfield(Main, :Parquet2)
        df_mod = getfield(Main, :DataFrames)
        return Base.invokelatest(getfield(df_mod, :DataFrame), Base.invokelatest(getfield(pq_mod, :readfile), artifact_path))
    elseif s in ("text", "txt")
        return read(artifact_path, String)
    elseif s == "pmml"
        error(
            "Node artifact uses serializer `^pmml`, which has no built-in Julia reader here. " *
            "Use `return_path=true` plus a custom `deserializer` to inspect the file."
        )
    elseif s == "onnx"
        error(
            "Node artifact uses serializer `^onnx`, which has no built-in Julia reader here. " *
            "Use `return_path=true` plus a custom `deserializer` to inspect the file."
        )
    elseif s == "bin"
        error(
            "Node artifact uses serializer `^bin` (opaque bytes). Use `return_path=true` to get the artifact path or pass a custom `deserializer`."
        )
    else
        # Unknown serializer (e.g. custom formats): raise a clear error
        # consistent with how R and Python read_node behave on formats they
        # cannot deserialize. Use return_path=true or pass a custom deserializer.
        error(
            "read_node: no built-in deserializer for serializer \"$serializer\" (normalized to `$s`). " *
            "Pass a custom `deserializer` function or use `return_path=true` to get the artifact path."
        )
    end
end

"""
    _read_node_entry(node_entry, name, pipeline_dir, deserializer, return_path)

Deserialize one already-located build-log entry. Shared by `read_node()` and
`read_node_tree()` so a tree read uses the single already-selected build log
instead of re-resolving `which_log` per node.
"""
function _read_node_entry(node_entry, name::String, pipeline_dir::String, deserializer, return_path::Bool)
    artifact_path = _resolve_artifact_path(node_entry["path"], pipeline_dir)
    if return_path
        return artifact_path
    end
    actual_deserializer =
        if !isnothing(deserializer)
            (path) -> deserializer(path)
        else
            serializer_name = get(node_entry, "serializer", "default")
            (path) -> _auto_deserializer(serializer_name isa String ? serializer_name : "default", path)
        end
    try
        return actual_deserializer(artifact_path)
    catch e
        error("Failed to deserialize node `$name` from `$artifact_path`: $e")
    end
end

"""
    read_node(name::String; which_log::Union{String, Nothing} = nothing, pipeline_dir::String = \"_pipeline\", deserializer::Union{Function, Nothing} = nothing, return_path::Bool = false)

Read a node artifact from a built T pipeline.

Locates the requested node in the build log and deserializes its artifact.
When `which_log` is `nothing`, the helper picks the first reverse-alphabetically
sorted `build_log_*.json` file, which matches T's timestamped log naming and
therefore resolves to the most recent build.

If no `deserializer` is provided, the serializer recorded in the build log is used
to pick the right one automatically:
- `default`/`tlang` → `Serialization.deserialize(path)`
- `csv`  → `CSV.read(path, DataFrame)` (requires `using CSV, DataFrames`)
- `json` → `JSON.parsefile(path)`
- `ipc` → `Arrow.Table(path) |> DataFrame` (requires `using Arrow, DataFrames`)
- `parquet` → `DataFrame(Parquet2.readfile(path))` (requires `using Parquet2, DataFrames`)
- `text` → `read(path, String)` (exact bytes as text)
- `pmml`/`onnx`/`bin`/unknown → explicit error suggesting `return_path=true`
  or a custom `deserializer`.

# Arguments
- `name::String`: The name of the node to retrieve.

# Keywords
- `which_log::Union{String, Nothing}`: An optional regex pattern used to select a specific build log file by name.
  If `nothing`, the most recent build log is used.
- `pipeline_dir::String`: The path to the pipeline directory. Defaults to `\"_pipeline\"`.
- `deserializer::Union{Function, Nothing}`: A function to deserialize the node artifact from disk.
  When `nothing` (the default), the serializer field in the build log is used to pick automatically.
- `return_path::Bool`: If `true`, return the absolute path to the artifact file instead of deserializing it.
  Defaults to `false`.

# Returns
- `Any`: The deserialized node artifact, or a string representing the absolute path to the
  artifact file if `return_path` is `true`.

# Throws
- `ErrorException`: If the pipeline directory, build log, or matching log cannot be found, if the node
  cannot be found, or if deserialization fails.
"""
function read_node(
    name::String;
    which_log::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline",
    deserializer::Union{Function, Nothing} = nothing,
    return_path::Bool = false
)
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    
    logs = _list_build_logs(pipeline_dir)
    log_file = _select_build_log(logs, which_log, pipeline_dir)
    log_path = joinpath(pipeline_dir, log_file)
    
    build_log = JSON.parsefile(log_path)
    if !haskey(build_log, "nodes") || !(build_log["nodes"] isa Vector)
        error("Build log `$log_file` does not contain a `nodes` array.")
    end
    
    node_entry = _find_node_entry(build_log["nodes"], name, log_file)
    return _read_node_entry(node_entry, name, pipeline_dir, deserializer, return_path)
end

"""
    _build_log_deps_map(nodes::Vector)

Build a node -> dependencies map from a build-log nodes array.
"""
function _build_log_deps_map(nodes::Vector)
    deps = Dict{String, Vector{String}}()
    for entry in nodes
        if !(entry isa AbstractDict)
            continue
        end
        nm = get(entry, "node", nothing)
        if !(nm isa String) || isempty(strip(nm))
            continue
        end
        raw = get(entry, "dependencies", String[])
        if isnothing(raw)
            raw = String[]
        end
        clean = String[]
        if raw isa Vector
            for d in raw
                if d isa String && !isempty(strip(d))
                    push!(clean, d)
                end
            end
        end
        deps[nm] = unique(sort(clean))
    end
    return deps
end

"""
    _closure_nodes(deps::Dict{String, Vector{String}}, name::String, include::String)

Compute the transitive closure over parents, children, or both. Returns the
root first, then the rest in visit order.
"""
function _closure_nodes(deps::Dict{String, Vector{String}}, name::String, include::String)
    if !(include in ("children", "parents", "both"))
        error("`include` must be one of \"children\", \"parents\", \"both\".")
    end
    if !haskey(deps, name)
        error("Node `$name` not found in build log.")
    end
    children_map = Dict{String, Vector{String}}()
    for (node, ds) in deps
        for dep in ds
            push!(get!(children_map, dep, String[]), node)
        end
    end
    seen = String[name]
    seen_set = Set(seen)
    queue = String[name]
    while !isempty(queue)
        current = popfirst!(queue)
        neighbors = String[]
        if include in ("children", "both")
            append!(neighbors, get(children_map, current, String[]))
        end
        if include in ("parents", "both")
            append!(neighbors, get(deps, current, String[]))
        end
        for nb in neighbors
            if !(nb in seen_set)
                push!(seen_set, nb)
                push!(seen, nb)
                push!(queue, nb)
            end
        end
    end
    missing_deps = sort(collect(setdiff(Set(seen), Set(keys(deps)))))
    if !isempty(missing_deps)
        error("Build log references unknown dependencies: $(join(missing_deps, ", ")).")
    end
    return seen
end

"""
    read_node_tree(name::String; which_log=nothing, pipeline_dir="_pipeline", deserializer=nothing, return_path=false, include="children", on_unreadable="error")

Read a node and all of its related nodes.

Reads the requested node plus its transitive `children` (nodes that depend
on it), `parents` (nodes it depends on), or `both`. Each node uses the
serializer recorded in the build log unless `deserializer` is a function,
in which case that function reads every node. All nodes come from the single
build log selected up front.

A single unreadable node aborts the whole tree by default. Pass
`on_unreadable="path"` to fall back to the artifact path for nodes that fail
to deserialize (for example `^pmml` model artifacts downstream), or
`on_unreadable="skip"` to omit them. Both fallbacks warn naming the node and
the error. `return_path=true` returns every path and never triggers the fallback.

# Arguments
- `name::String`: The root node name.

# Keywords
- `which_log::Union{String, Nothing}`: Regex to select a build log. Defaults to latest.
- `pipeline_dir::String`: Pipeline directory. Defaults to `"_pipeline"`.
- `deserializer::Union{Function, Nothing}`: Override reader for every node. Defaults to per-node auto.
- `return_path::Bool`: Return artifact paths instead of values. Defaults to `false`.
- `include::String`: One of `"children"` (default), `"parents"`, `"both"`.
- `on_unreadable::String`: One of `"error"` (default), `"path"`, `"skip"`.

# Returns
- `Dict{String, Any}`: Mapping of node name to value (or path).
"""
function read_node_tree(
    name::String;
    which_log::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline",
    deserializer::Union{Function, Nothing} = nothing,
    return_path::Bool = false,
    include::String = "children",
    on_unreadable::String = "error"
)
    if !(include in ("children", "parents", "both"))
        error("`include` must be one of \"children\", \"parents\", \"both\".")
    end
    if !(on_unreadable in ("error", "path", "skip"))
        error("`on_unreadable` must be one of \"error\", \"path\", \"skip\".")
    end
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    logs = _list_build_logs(pipeline_dir)
    log_file = _select_build_log(logs, which_log, pipeline_dir)
    log_path = joinpath(pipeline_dir, log_file)
    build_log = JSON.parsefile(log_path)
    if !haskey(build_log, "nodes") || !(build_log["nodes"] isa Vector)
        error("Build log `$log_file` does not contain a `nodes` array.")
    end
    deps = _build_log_deps_map(build_log["nodes"])
    wanted = _closure_nodes(deps, name, include)
    entries = Dict{String, Any}()
    for entry in build_log["nodes"]
        if entry isa AbstractDict && haskey(entry, "node") && entry["node"] isa String
            entries[entry["node"]] = entry
        end
    end
    result = Dict{String, Any}()
    for node_name in wanted
        if return_path
            result[node_name] = _read_node_entry(
                entries[node_name], node_name, pipeline_dir, deserializer, true
            )
            continue
        end
        try
            result[node_name] = _read_node_entry(
                entries[node_name], node_name, pipeline_dir, deserializer, false
            )
        catch e
            e isa InterruptException && rethrow()
            if on_unreadable == "error"
                rethrow(e)
            end
            msg = sprint(showerror, e)
            @warn "Node `$node_name` could not be deserialized ($msg); $(on_unreadable == "path" ? "returning the artifact path." : "skipping it.")"
            if on_unreadable == "path"
                result[node_name] = _resolve_artifact_path(
                    entries[node_name]["path"], pipeline_dir
                )
            end
            # "skip": omit the node.
        end
    end
    return result
end

"""
    _inspect_text_or_nothing(value)

Return trimmed text or `nothing` for missing values.
"""
function _inspect_text_or_nothing(value)
    if value isa String && !isempty(strip(value))
        return strip(value)
    end
    return nothing
end

"""
    _inspect_status_of(entry)

Derive a display status from a build-log node entry. Prefers the `status`
string when present, else maps `success` (bool or "true"/"false" string) to
`Completed`/`SoftFailed`.
"""
function _inspect_status_of(entry)
    status = get(entry, "status", nothing)
    if status isa String && !isempty(strip(status))
        return strip(status)
    end
    success = get(entry, "success", nothing)
    if success isa Bool
        return success ? "Completed" : "SoftFailed"
    end
    if success isa String && !isempty(strip(success))
        return lowercase(strip(success)) == "true" ? "Completed" : "SoftFailed"
    end
    return nothing
end

"""
    inspect_pipeline(; pipeline_dir="_pipeline", which_log=nothing, dag_file="dag.json")

Inspect pipeline nodes and their latest build status.

Reads the selected build log and returns one `Dict` per node with `node`,
`runtime`, `serializer`, `dependencies`, `status`, `class`, and `path`. When
no build logs exist, falls back to the static DAG file with `status` set to
`"unbuilt"`.

# Keywords
- `pipeline_dir::String`: Pipeline directory. Defaults to `"_pipeline"`.
- `which_log::Union{String, Nothing}`: Regex to select a build log. Defaults to latest.
- `dag_file::String`: DAG filename used only when no build logs exist. Defaults to `"dag.json"`.

# Returns
- `Vector{Dict{String, Any}}`: One dict per node.
"""
function inspect_pipeline(;
    pipeline_dir::String = "_pipeline",
    which_log::Union{String, Nothing} = nothing,
    dag_file::String = "dag.json"
)
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    logs = _list_build_logs(pipeline_dir)
    if isempty(logs)
        dag_path = joinpath(pipeline_dir, dag_file)
        if !isfile(dag_path)
            error("DAG file `$dag_path` does not exist.")
        end
        dag = try
            JSON.parsefile(dag_path)
        catch e
            error("Failed to read DAG file `$dag_path`: $e")
        end
        if !(dag isa Vector)
            error("DAG file `$dag_path` must decode to an array.")
        end
        rows = Dict{String, Any}[]
        for (idx, entry) in enumerate(dag)
            node_name, deps = _validate_node_entry(entry, idx, dag_path)
            push!(rows, Dict{String, Any}(
                "node" => node_name,
                "runtime" => nothing,
                "serializer" => nothing,
                "dependencies" => deps,
                "status" => "unbuilt",
                "class" => nothing,
                "path" => nothing,
            ))
        end
        return rows
    end
    log_file = _select_build_log(logs, which_log, pipeline_dir)
    log_path = joinpath(pipeline_dir, log_file)
    build_log = JSON.parsefile(log_path)
    if !haskey(build_log, "nodes") || !(build_log["nodes"] isa Vector)
        error("Build log `$log_file` does not contain a `nodes` array.")
    end
    rows = Dict{String, Any}[]
    for entry in build_log["nodes"]
        if !(entry isa AbstractDict)
            continue
        end
        nm = get(entry, "node", nothing)
        if !(nm isa String) || isempty(strip(nm))
            continue
        end
        raw = get(entry, "dependencies", String[])
        clean = String[]
        if raw isa Vector
            for d in raw
                if d isa String && !isempty(strip(d))
                    push!(clean, d)
                end
            end
        end
        artifact = try
            _resolve_artifact_path(entry["path"], pipeline_dir)
        catch
            nothing
        end
        push!(rows, Dict{String, Any}(
            "node" => nm,
            "runtime" => _inspect_text_or_nothing(get(entry, "runtime", nothing)),
            "serializer" => _inspect_text_or_nothing(get(entry, "serializer", nothing)),
            "dependencies" => unique(sort(clean)),
            "status" => _inspect_status_of(entry),
            "class" => _inspect_text_or_nothing(get(entry, "class", nothing)),
            "path" => artifact,
        ))
    end
    return rows
end

"""
    _frames_clean_message(message)

Keep the last non-empty message line, truncated like T (max 100 chars).
"""
function _frames_clean_message(message)
    if !(message isa String)
        return ""
    end
    lines = filter(l -> !isempty(strip(l)), map(strip, split(message, '\n')))
    last_line = isempty(lines) ? "" : lines[end]
    return length(last_line) > 100 ? last_line[1:97] * "..." : last_line
end

"""
    _frames_status_of(entry)

Derive a display status from a build-log node entry. Prefers the `status`
string when present, else maps `success` (bool or "true"/"false" string) to
`Completed`/`SoftFailed`.
"""
function _frames_status_of(entry)
    status = get(entry, "status", nothing)
    if status isa String && !isempty(strip(status))
        return strip(status)
    end
    success = get(entry, "success", nothing)
    if success isa Bool
        return success ? "Completed" : "SoftFailed"
    end
    if success isa String && !isempty(strip(success))
        return lowercase(strip(success)) == "true" ? "Completed" : "SoftFailed"
    end
    return nothing
end

"""
    _frames_duration_of(entry)

Parse a duration value to float, or `nothing` when absent.
"""
function _frames_duration_of(entry)
    duration = get(entry, "duration", nothing)
    if duration isa Bool || isnothing(duration)
        return nothing
    end
    if duration isa Number
        return Float64(duration)
    end
    if duration isa String && !isempty(strip(duration))
        parsed = tryparse(Float64, strip(duration))
        return isnothing(parsed) ? nothing : parsed
    end
    return nothing
end

"""
    _frames_warning_rows(name, entry)

Read warning rows from the per-artifact `warnings` sidecar (a JSON array of
strings or `{kind, message}` dicts next to the artifact).
"""
function _frames_warning_rows(name::String, entry)
    flag = get(entry, "warnings", false)
    has_warnings = if flag isa Bool
        flag
    elseif flag isa String
        lowercase(strip(flag)) == "true"
    else
        false
    end
    if !has_warnings
        return Dict{String, Any}[]
    end
    path_val = get(entry, "path", nothing)
    if !(path_val isa String) || isempty(strip(path_val))
        return Dict{String, Any}[]
    end
    sidecar = joinpath(dirname(path_val), "warnings")
    items = try
        JSON.parsefile(sidecar)
    catch
        return Dict{String, Any}[]
    end
    if !(items isa Vector)
        return Dict{String, Any}[]
    end
    rows = Dict{String, Any}[]
    for item in items
        if item isa String
            push!(rows, Dict{String, Any}(
                "node" => name, "status" => "Warning",
                "code" => "Generic", "message" => item))
        elseif item isa AbstractDict
            kind = get(item, "kind", nothing)
            msg = get(item, "message", nothing)
            push!(rows, Dict{String, Any}(
                "node" => name, "status" => "Warning",
                "code" => (kind isa String && !isempty(strip(kind)) ? kind : "Generic"),
                "message" => (msg isa String ? msg : "")))
        end
    end
    return rows
end

"""
    _format_mtime(mtime)

Format a Unix timestamp as local `%Y-%m-%d %H:%M:%S` via libc, matching the
`list_logs()` layout without extra dependencies.
"""
function _format_mtime(mtime::Float64)
    secs = Ref{Int}(Int(floor(mtime)))
    tm = Ref(Base.Libc.TmStruct(0, 0, 0, 0, 0, 0, 0, 0, 0))
    ccall(:localtime_r, Ptr{Cvoid}, (Ref{Int}, Ptr{Cvoid}), secs, tm)
    return Base.Libc.strftime("%Y-%m-%d %H:%M:%S", tm[])
end

"""
    list_logs(; pipeline_dir="_pipeline")

List build logs in the pipeline directory, newest first. Each row has
`filename`, `modification_time` (`%Y-%m-%d %H:%M:%S`), `size_kb`, and
`pipeline`. Mirrors T's `list_logs()`.
"""
function list_logs(; pipeline_dir::String = "_pipeline")
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    rows = Dict{String, Any}[]
    for name in _list_build_logs(pipeline_dir)
        full = joinpath(pipeline_dir, name)
        st = try
            stat(full)
        catch
            continue
        end
        logged = try
            JSON.parsefile(full)
        catch
            nothing
        end
        pipeline = if logged isa AbstractDict && get(logged, "pipeline", nothing) isa String
            logged["pipeline"]
        else
            nothing
        end
        mtime = _format_mtime(Float64(st.mtime))
        push!(rows, Dict{String, Any}(
            "filename" => name,
            "modification_time" => mtime,
            "size_kb" => round(st.size / 1024, digits=2),
            "pipeline" => pipeline,
        ))
    end
    return rows
end

"""
    build_log_to_frame(; which_log=nothing, pipeline_dir="_pipeline")

Tabulate one build log as per-node rows with `name`, `status`, `duration`,
and `path`. Mirrors T's `build_log_to_frame()`.
"""
function build_log_to_frame(;
    which_log::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline"
)
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    logs = _list_build_logs(pipeline_dir)
    log_file = _select_build_log(logs, which_log, pipeline_dir)
    build_log = JSON.parsefile(joinpath(pipeline_dir, log_file))
    if !haskey(build_log, "nodes") || !(build_log["nodes"] isa Vector)
        error("Build log `$log_file` does not contain a `nodes` array.")
    end
    rows = Dict{String, Any}[]
    for entry in build_log["nodes"]
        if !(entry isa AbstractDict)
            continue
        end
        nm = get(entry, "node", nothing)
        if !(nm isa String) || isempty(strip(nm))
            continue
        end
        path_val = get(entry, "path", nothing)
        push!(rows, Dict{String, Any}(
            "name" => nm,
            "status" => _frames_status_of(entry),
            "duration" => _frames_duration_of(entry),
            "path" => (path_val isa String ? path_val : nothing),
        ))
    end
    return rows
end

"""
    collect_exceptions(; which_log=nothing, pipeline_dir="_pipeline")

Gather error and warning rows from one build log. Each row has `node`,
`status` (`Error`/`Warning`), `code`, and `message`. Mirrors T's
`collect_exceptions()`.
"""
function collect_exceptions(;
    which_log::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline"
)
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    logs = _list_build_logs(pipeline_dir)
    log_file = _select_build_log(logs, which_log, pipeline_dir)
    build_log = JSON.parsefile(joinpath(pipeline_dir, log_file))
    if !haskey(build_log, "nodes") || !(build_log["nodes"] isa Vector)
        error("Build log `$log_file` does not contain a `nodes` array.")
    end
    rows = Dict{String, Any}[]
    for entry in build_log["nodes"]
        if !(entry isa AbstractDict)
            continue
        end
        nm = get(entry, "node", nothing)
        if !(nm isa String) || isempty(strip(nm))
            continue
        end
        status = _frames_status_of(entry)
        class_val = get(entry, "class", "")
        class_val = class_val isa String ? class_val : ""
        if status == "Errored"
            code = get(entry, "error_code", nothing)
            msg = _frames_clean_message(get(entry, "error_message", ""))
            push!(rows, Dict{String, Any}(
                "node" => nm, "status" => "Error",
                "code" => (code isa String && !isempty(strip(code)) ? code : "NixError"),
                "message" => (isempty(msg) ? "Nix build failed." : msg)))
        elseif status == "SoftFailed" || class_val in ("VError", "Error")
            code = get(entry, "error_code", nothing)
            msg = _frames_clean_message(get(entry, "error_message", ""))
            push!(rows, Dict{String, Any}(
                "node" => nm, "status" => "Error",
                "code" => (code isa String && !isempty(strip(code)) ? code : (isempty(class_val) ? "Error" : class_val)),
                "message" => (isempty(msg) ? "Node failed with a soft error." : msg)))
        end
        append!(rows, _frames_warning_rows(nm, entry))
    end
    return rows
end

"""
    _load_inspect_entry(name, which_log, pipeline_dir)

Select the build log once and return `(entry, log_file, deps)`, so callers
never mix two snapshots.
"""
function _load_inspect_entry(name::String, which_log, pipeline_dir::String)
    logs = _list_build_logs(pipeline_dir)
    log_file = _select_build_log(logs, which_log, pipeline_dir)
    build_log = JSON.parsefile(joinpath(pipeline_dir, log_file))
    if !haskey(build_log, "nodes") || !(build_log["nodes"] isa Vector)
        error("Build log `$log_file` does not contain a `nodes` array.")
    end
    entry = _find_node_entry(build_log["nodes"], name, log_file)
    return entry, log_file, _build_log_deps_map(build_log["nodes"])
end

"""
    _verror_from_file(artifact_path)

Parse a VError JSON artifact, or `nothing` when it is not one.
Foreign-runtime failures are stored as VError JSON, so an R error message
reads the same from any language.
"""
function _verror_from_file(artifact_path::String)
    payload = try
        JSON.parsefile(artifact_path)
    catch
        return nothing
    end
    if !(payload isa AbstractDict) || get(payload, "type", nothing) != "VError"
        return nothing
    end
    code = get(payload, "code", nothing)
    message = get(payload, "message", nothing)
    context = get(payload, "context", nothing)
    location = get(payload, "location", nothing)
    return Dict{String, Any}(
        "code" => (code isa String && !isempty(strip(code)) ? code : "RuntimeError"),
        "message" => (message isa String ? message : "Unknown error"),
        "context" => (context isa AbstractDict ? context : nothing),
        "location" => (location isa AbstractDict ? location : nothing),
    )
end

"""
    _error_of_entry(entry, pipeline_dir)

Build a node error from an already-loaded entry (no log re-read).
"""
function _error_of_entry(entry, pipeline_dir::String)
    artifact = try
        _resolve_artifact_path(entry["path"], pipeline_dir)
    catch
        nothing
    end
    if !isnothing(artifact)
        verror = _verror_from_file(artifact)
        if !isnothing(verror)
            return verror
        end
    end
    code = get(entry, "error_code", nothing)
    message = get(entry, "error_message", nothing)
    code_ok = code isa String && !isempty(strip(code))
    msg_ok = message isa String && !isempty(strip(message))
    if code_ok || msg_ok
        return Dict{String, Any}(
            "code" => (code_ok ? code : "Error"),
            "message" => (msg_ok ? message : ""),
            "context" => nothing,
            "location" => nothing,
        )
    end
    return nothing
end

"""
    _require_node_error(entry, name, pipeline_dir, func)

Return the node's error dict, or throw when the node is healthy (mirrors T,
where `error_msg()` on a healthy node is a `TypeError`).
"""
function _require_node_error(entry, name::String, pipeline_dir::String, func::String)
    verror = _error_of_entry(entry, pipeline_dir)
    if isnothing(verror)
        error("Function `$func` expects a failed node, but node `$name` has no error.")
    end
    return verror
end

"""
    error_msg(name::String; which_log=nothing, pipeline_dir="_pipeline")

Return a failed node's human-readable error message. Mirrors T's
`error_msg()`.
"""
function error_msg(
    name::String;
    which_log::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline"
)
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    entry, _, _ = _load_inspect_entry(name, which_log, pipeline_dir)
    return _require_node_error(entry, name, pipeline_dir, "error_msg")["message"]
end

"""
    error_code(name::String; which_log=nothing, pipeline_dir="_pipeline")

Return a failed node's error code. Mirrors T's `error_code()`.
"""
function error_code(
    name::String;
    which_log::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline"
)
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    entry, _, _ = _load_inspect_entry(name, which_log, pipeline_dir)
    return _require_node_error(entry, name, pipeline_dir, "error_code")["code"]
end

"""
    error_context(name::String; which_log=nothing, pipeline_dir="_pipeline")

Return a failed node's error context dict (possibly empty). Mirrors T's
`error_context()`.
"""
function error_context(
    name::String;
    which_log::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline"
)
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    entry, _, _ = _load_inspect_entry(name, which_log, pipeline_dir)
    context = _require_node_error(entry, name, pipeline_dir, "error_context")["context"]
    return context isa AbstractDict ? context : Dict{String, Any}()
end

"""
    warning_msg(name::String; which_log=nothing, pipeline_dir="_pipeline")

Return a node's formatted warnings, or `""` when none. Upstream warnings are
prefixed with the source node name, and multiple warnings join with
`". Furthermore, "`. Mirrors T's `warning_msg()`.
"""
function warning_msg(
    name::String;
    which_log::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline"
)
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    logs = _list_build_logs(pipeline_dir)
    log_file = _select_build_log(logs, which_log, pipeline_dir)
    build_log = JSON.parsefile(joinpath(pipeline_dir, log_file))
    if !haskey(build_log, "nodes") || !(build_log["nodes"] isa Vector)
        error("Build log `$log_file` does not contain a `nodes` array.")
    end
    _find_node_entry(build_log["nodes"], name, log_file)
    deps = _build_log_deps_map(build_log["nodes"])
    entries = Dict{String, Any}()
    for entry in build_log["nodes"]
        if entry isa AbstractDict && haskey(entry, "node") && entry["node"] isa String
            entries[entry["node"]] = entry
        end
    end
    messages = String[]
    for row in _frames_warning_rows(name, entries[name])
        push!(messages, row["message"])
    end
    for parent in _closure_nodes(deps, name, "parents")[2:end]
        for row in _frames_warning_rows(parent, entries[parent])
            push!(messages, "Ancestor node '$parent' reported following warning: $(row["message"])")
        end
    end
    return join(messages, ". Furthermore, ")
end

"""
    inspect_node(name::String; which_log=nothing, pipeline_dir="_pipeline")

Inspect one node's metadata, lineage, error, and warnings. Returns a `Dict`
with `name`, `runtime`, `serializer`, `dependencies`, `children` (direct
dependents), `status`, `class`, `path`, `error`, and `warnings`.
"""
function inspect_node(
    name::String;
    which_log::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline"
)
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    entry, _, deps = _load_inspect_entry(name, which_log, pipeline_dir)
    raw_deps = get(entry, "dependencies", String[])
    clean = String[]
    if raw_deps isa Vector
        for d in raw_deps
            if d isa String && !isempty(strip(d))
                push!(clean, d)
            end
        end
    end
    children = sort([n for (n, ds) in deps if name in ds])
    warn_rows = _frames_warning_rows(name, entry)
    warnings = [Dict{String, Any}("code" => w["code"], "message" => w["message"]) for w in warn_rows]
    artifact = try
        _resolve_artifact_path(entry["path"], pipeline_dir)
    catch
        nothing
    end
    status = let s = get(entry, "status", nothing)
        if s isa String && !isempty(strip(s))
            strip(s)
        else
            _frames_status_of(entry)
        end
    end
    return Dict{String, Any}(
        "name" => name,
        "runtime" => _inspect_text_or_nothing(get(entry, "runtime", nothing)),
        "serializer" => _inspect_text_or_nothing(get(entry, "serializer", nothing)),
        "dependencies" => unique(sort(clean)),
        "children" => children,
        "status" => status,
        "class" => _inspect_text_or_nothing(get(entry, "class", nothing)),
        "path" => artifact,
        "error" => _error_of_entry(entry, pipeline_dir),
        "warnings" => warnings,
    )
end

"""
    lineage(name::String; which_log=nothing, pipeline_dir="_pipeline", direction="both")

List a node's transitive parents and children (names only, nearest first).
Returns a `Dict` with `parents` and `children`; only the requested
directions are filled.
"""
function lineage(
    name::String;
    which_log::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline",
    direction::String = "both"
)
    if !(direction in ("parents", "children", "both"))
        error("`direction` must be one of \"parents\", \"children\", \"both\".")
    end
    if !isdir(pipeline_dir)
        error("Pipeline directory `$pipeline_dir` does not exist.")
    end
    _, _, deps = _load_inspect_entry(name, which_log, pipeline_dir)
    parents = String[]
    children = String[]
    if direction in ("parents", "both")
        full = _closure_nodes(deps, name, "parents")
        parents = full[2:end]
    end
    if direction in ("children", "both")
        full = _closure_nodes(deps, name, "children")
        children = full[2:end]
    end
    return Dict{String, Any}("parents" => parents, "children" => children)
end

"""
    load_deepdiffs()

Load DeepDiffs lazily so basic package imports still work until diff helpers are used.
"""
function load_deepdiffs()
    try
        Base.eval(@__MODULE__, :(import DeepDiffs))
    catch err
        error(
            "DeepDiffs is required for Julia object diffs. Instantiate the `tlang` Julia package environment so `node_diff()` can compare Julia artifacts. Original error: $err"
        )
    end

    return Base.invokelatest(getfield, @__MODULE__, :DeepDiffs)
end

"""
    shape_info(obj)

Return an object's dimensions as an integer vector when available.
"""
function shape_info(obj)
    try
        dims = size(obj)
        return isempty(dims) ? nothing : [Int(dim) for dim in dims]
    catch
        return nothing
    end
end

"""
    length_info(obj)

Return `length(obj)` when defined.
"""
function length_info(obj)
    try
        return length(obj)
    catch
        return nothing
    end
end

"""
    value_type(obj_a, obj_b; class_a=nothing, class_b=nothing)

Choose the most informative value type label for the diff envelope.
"""
function value_type(obj_a, obj_b; class_a=nothing, class_b=nothing)
    label_a = class_a isa String ? strip(class_a) : ""
    label_b = class_b isa String ? strip(class_b) : ""

    if !isempty(label_a) && label_a == label_b
        return label_a
    end

    if !isempty(label_a) && !isempty(label_b)
        return string(label_a, " -> ", label_b)
    end

    type_a = string(typeof(obj_a))
    type_b = string(typeof(obj_b))
    return type_a == type_b ? type_a : string(type_a, " -> ", type_b)
end

"""
    render_deepdiff(diff)

Render a DeepDiffs diff object to a plain-text summary.
"""
function render_deepdiff(diff)
    rendered = sprint(show, MIME"text/plain"(), diff)
    return isempty(strip(rendered)) ? sprint(show, diff) : rendered
end

"""
    diff_objects(obj_a, obj_b; ...)

Diff two Julia objects and return a T-compatible VDiff envelope.
"""
function diff_objects(
    obj_a,
    obj_b;
    node_a::String = "node_a",
    node_b::String = "node_b",
    log_a::String = "latest",
    log_b::String = "latest",
    class_a = nothing,
    class_b = nothing,
    context::Integer = 3
)
    deepdiffs = load_deepdiffs()
    deepdiff = Base.invokelatest(getfield, deepdiffs, :deepdiff)
    diff = Base.invokelatest(deepdiff, obj_a, obj_b)
    identical_objects = isequal(obj_a, obj_b)
    rendered = identical_objects ? "Objects are identical." : render_deepdiff(diff)
    lines =
        identical_objects ? String[] :
        filter(line -> !isempty(strip(line)), split(rendered, '\n'))

    summary = Dict{String, Any}(
        "changes" => identical_objects ? 0 : length(lines),
        "typeof_a" => string(typeof(obj_a)),
        "typeof_b" => string(typeof(obj_b)),
    )

    len_a = length_info(obj_a)
    len_b = length_info(obj_b)
    if !isnothing(len_a)
        summary["length_a"] = len_a
    end
    if !isnothing(len_b)
        summary["length_b"] = len_b
    end

    shape_a = shape_info(obj_a)
    shape_b = shape_info(obj_b)
    if !isnothing(shape_a)
        summary["shape_a"] = shape_a
    end
    if !isnothing(shape_b)
        summary["shape_b"] = shape_b
    end

    detail =
        identical_objects ? Dict{String, Any}() :
        Dict{String, Any}(
            "renderer" => "DeepDiffs",
            "lines" => lines,
        )

    return Dict{String, Any}(
        "kind" => "julia_object_diff",
        "node_a" => node_a,
        "node_b" => node_b,
        "log_a" => log_a,
        "log_b" => log_b,
        "value_type" => value_type(obj_a, obj_b, class_a=class_a, class_b=class_b),
        "identical" => identical_objects,
        "summary" => summary,
        "detail" => detail,
        "detailed_diff" => rendered,
        "detailed_summary" => rendered,
        "hunks" => Any[],
    )
end

"""
    diff_artifacts(path_a, path_b; ...)

Deserialize two artifacts and diff the resulting Julia objects.
"""
function diff_artifacts(
    path_a::Union{String, AbstractString},
    path_b::Union{String, AbstractString};
    node_a::String = "node_a",
    node_b::String = "node_b",
    log_a::String = "latest",
    log_b::String = "latest",
    class_a = nothing,
    class_b = nothing,
    context::Integer = 3,
    deserializer::Function = Serialization.deserialize
)
    obj_a = deserializer(path_a)
    obj_b = deserializer(path_b)
    return diff_objects(
        obj_a,
        obj_b,
        node_a=node_a,
        node_b=node_b,
        log_a=log_a,
        log_b=log_b,
        class_a=class_a,
        class_b=class_b,
        context=context,
    )
end

"""
    diff_nodes(node_a, node_b; ...)

Load two nodes via `read_node()` and diff their deserialized Julia objects.
"""
function diff_nodes(
    node_a::String,
    node_b::String;
    which_log_a::Union{String, Nothing} = nothing,
    which_log_b::Union{String, Nothing} = nothing,
    pipeline_dir::String = "_pipeline",
    context::Integer = 3,
    deserializer::Function = Serialization.deserialize
)
    path_a = read_node(node_a, which_log=which_log_a, pipeline_dir=pipeline_dir, return_path=true)
    path_b = read_node(node_b, which_log=which_log_b, pipeline_dir=pipeline_dir, return_path=true)

    return diff_artifacts(
        path_a,
        path_b,
        node_a=node_a,
        node_b=node_b,
        log_a=isnothing(which_log_a) ? "latest" : which_log_a,
        log_b=isnothing(which_log_b) ? "latest" : which_log_b,
        context=context,
        deserializer=deserializer,
    )
end

end # module

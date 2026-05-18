module tlang

using JSON
using Serialization

export read_node, pipeline_nodes

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
    read_node(name::String; which_log::Union{String, Nothing} = nothing, pipeline_dir::String = "_pipeline", deserializer::Function = Serialization.deserialize, return_path::Bool = false)

Read a node artifact from a built T pipeline.

Locates the requested node in the build log and deserializes its artifact.
When `which_log` is `nothing`, the helper picks the first reverse-alphabetically
sorted `build_log_*.json` file, which matches T's timestamped log naming and
therefore resolves to the most recent build.

# Arguments
- `name::String`: The name of the node to retrieve.

# Keywords
- `which_log::Union{String, Nothing}`: An optional regex pattern used to select a specific build log file by name.
  If `nothing`, the most recent build log is used.
- `pipeline_dir::String`: The path to the pipeline directory. Defaults to `"_pipeline"`.
- `deserializer::Function`: A function to deserialize the node artifact from disk.
  Defaults to `Serialization.deserialize`.
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
    deserializer::Function = Serialization.deserialize,
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
    artifact_path = _resolve_artifact_path(node_entry["path"], pipeline_dir)
    
    if return_path
        return artifact_path
    end
    
    try
        return deserializer(artifact_path)
    catch e
        error("Failed to deserialize node `$name` from `$artifact_path`: $e")
    end
end

end # module

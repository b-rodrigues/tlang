module tlang

using JSON
using Serialization

export read_node, pipeline_nodes, diff_artifacts, diff_nodes, diff_objects

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
    _auto_deserializer(serializer::String, artifact_path::String)

Pick a deserializer based on the serializer name recorded in the build log.

Supports `"csv"` (loads via CSV.jl + DataFrames.jl when available, falls back to
reading the raw file as a string), `"json"` (parses with JSON.jl), and everything
else falls back to `Serialization.deserialize`.
"""
function _auto_deserializer(serializer::String, artifact_path::String)
    s = lowercase(strip(serializer))
    if s == "csv"
        # Try CSV.jl + DataFrames.jl; give a clear message if they are not loaded.
        if !isdefined(Main, :CSV) || !isdefined(Main, :DataFrames)
            error(
                "Node artifact is a CSV file but `CSV` and `DataFrames` are not loaded. " *
                "Run `using CSV, DataFrames` first, then call read_node() again."
            )
        end
        csv_mod = getfield(Main, :CSV)
        df_mod  = getfield(Main, :DataFrames)
        return Base.invokelatest(getfield(csv_mod, :read), artifact_path, getfield(df_mod, :DataFrame))
    elseif s == "json"
        return JSON.parsefile(artifact_path)
    elseif s == "default" || s == "tobj"
        # Julia-native binary formats — use Julia's own serializer.
        return Serialization.deserialize(artifact_path)
    else
        # Unknown serializer (e.g. pmml, parquet, rds): raise a clear error
        # consistent with how R and Python read_node behave on formats they
        # cannot deserialize. Use return_path=true or pass a custom deserializer.
        error(
            "read_node: no built-in deserializer for serializer \"$serializer\". " *
            "Pass a custom `deserializer` function or use `return_path=true` to get the artifact path."
        )
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
- `csv`  → `CSV.read(path, DataFrame)` (requires `using CSV, DataFrames`)
- `json` → `JSON.parsefile(path)`
- anything else → `Serialization.deserialize(path)`

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

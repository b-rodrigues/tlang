module tlang

using JSON
using Serialization

export read_node

const FIXTURE_LOGS = ["build_log_ocaml_mock.json", "build_log_legacy_version.json"]

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

function _select_build_log(logs::Vector{String}, which_log::Union{String, Nothing}, pipeline_dir::String)
    if isnothing(which_log)
        if isempty(logs)
            error("No build logs found in `$pipeline_dir`. Build the pipeline first.")
        end
        return logs[1]
    end
    
    pattern = Regex(which_log)
    matches = filter(l -> occursin(pattern, l), logs)
    
    if isempty(matches)
        error("No build logs found in `$pipeline_dir` matching \"$which_log\".")
    end
    
    return matches[1]
end

function _find_node_entry(nodes::Vector{Any}, name::String, log_file::String)
    for entry in nodes
        if entry isa Dict && get(entry, "node", nothing) == name
            return entry
        end
    end
    error("Node `$name` not found in build log `$log_file`.")
end

function _resolve_artifact_path(path_val::String, pipeline_dir::String)
    if isabspath(path_val)
        return path_val
    end
    # The artifact path in the log is relative to the project root (parent of _pipeline)
    return abspath(joinpath(dirname(abspath(pipeline_dir)), path_val))
end

"""
    read_node(name::String; which_log=nothing, pipeline_dir="_pipeline", deserializer=Serialization.deserialize, return_path=false)

Read a node artifact from a built T pipeline.
Locates the requested node in the build log and deserializes its artifact.
If `return_path` is true, the path to the artifact is returned instead of the deserialized object.
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

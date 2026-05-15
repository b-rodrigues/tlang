module tlang

using JSON
using Serialization

export read_node, pipeline_nodes

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

function _find_node_entry(nodes::Vector{Any}, name::String, log_file::String)
    for entry in nodes
        if entry isa AbstractDict && get(entry, "node", nothing) == name
            return entry
        end
    end
    error("Node `$name` not found in build log `$log_file`.")
end


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

function _render_node_tree(node::String, children_map::Dict{String, Vector{String}}; prefix::String="", is_last::Bool=true, seen::Vector{String}=String[], depth::Int=0)
    connector = depth == 0 ? "" : (is_last ? "\\- " : "|- ")
    line = string(prefix, connector, node)

    if node in seen
        cycle_prefix = string(prefix, is_last ? "   " : "|  ")
        return [line, string(cycle_prefix, "(cycle detected)")]
    end

    children = get(children_map, node, String[])
    if isempty(children)
        return [line]
    end

    next_prefix = string(prefix, is_last ? "   " : "|  ")
    lines = String[line]
    for (idx, child) in enumerate(children)
        append!(lines, _render_node_tree(child, children_map; prefix=next_prefix, is_last=(idx == length(children)), seen=vcat(seen, [node]), depth=depth+1))
    end

    return lines
end

"""
    pipeline_nodes(; pipeline_dir="_pipeline", dag_file="dag.json")

List pipeline nodes from `_pipeline/dag.json` in a tree-like view.
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

    children_map = Dict(name => String[] for name in node_names)
    incoming_count = Dict(name => 0 for name in node_names)

    for (name, deps) in normalized
        for parent in deps
            push!(children_map[parent], name)
            incoming_count[name] += 1
        end
    end

    for (key, children) in children_map
        sort!(children)
        children_map[key] = children
    end

    roots = sort([name for (name, count) in incoming_count if count == 0])
    if isempty(roots)
        roots = sort(node_names)
    end

    lines = String[]
    for (idx, root) in enumerate(roots)
        append!(lines, _render_node_tree(root, children_map; prefix="", is_last=(idx == length(roots))))
    end

    return join(lines, "\n")
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

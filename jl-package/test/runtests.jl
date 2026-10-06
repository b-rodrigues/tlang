using JSON
using Serialization
using Test
using tlang

struct ModelSnapshot
    weights::Vector{Float64}
    metadata::Dict{String, Any}
end

function write_artifact(path::AbstractString, value)
    open(path, "w") do io
        Serialization.serialize(io, value)
    end
    return path
end

@testset "Julia node diff helpers" begin
    mktempdir() do tmp_dir
        artifact_a = write_artifact(
            joinpath(tmp_dir, "a.jls"),
            ModelSnapshot([0.1, 0.2, 0.3], Dict("label" => "baseline", "active" => true)),
        )
        artifact_b = write_artifact(
            joinpath(tmp_dir, "b.jls"),
            ModelSnapshot([0.1, 0.25, 0.3], Dict("label" => "candidate", "active" => true)),
        )

        diff = tlang.diff_artifacts(
            artifact_a,
            artifact_b,
            node_a="weights",
            node_b="weights",
            class_a="ModelSnapshot",
            class_b="ModelSnapshot",
        )

        @test diff["kind"] == "julia_object_diff"
        @test diff["identical"] == false
        @test diff["value_type"] == "ModelSnapshot"
        @test diff["summary"]["changes"] > 0
        @test diff["detail"]["renderer"] == "DeepDiffs"
        @test !isempty(diff["detail"]["lines"])
    end

    mktempdir() do tmp_dir
        artifact_a = write_artifact(joinpath(tmp_dir, "a.jls"), Dict("a" => [1, 2, 3]))
        artifact_b = write_artifact(joinpath(tmp_dir, "b.jls"), Dict("a" => [1, 2, 3]))

        diff = tlang.diff_artifacts(artifact_a, artifact_b)

        @test diff["identical"] == true
        @test diff["summary"]["changes"] == 0
        @test isempty(diff["detail"])
    end
end

function _write_log(pipe::AbstractString, nodes, name::AbstractString)
    mkpath(pipe)
    open(joinpath(pipe, name), "w") do io
        JSON.print(io, Dict("nodes" => nodes))
    end
end

function _jl_node(name::AbstractString, path::AbstractString, serializer::AbstractString, deps)
    Dict(
        "node" => String(name),
        "path" => String(path),
        "serializer" => String(serializer),
        "dependencies" => collect(String, deps),
        "runtime" => "T",
        "class" => "String",
        "status" => "Completed",
    )
end

@testset "read_node auto dispatch and tree" begin
    @test tlang._normalize_serializer("^JSON") == "json"
    @test tlang._normalize_serializer("") == "default"

    mktempdir() do tmp_dir
        pipe = joinpath(tmp_dir, "_pipeline")
        payload = joinpath(tmp_dir, "v.json")
        open(payload, "w") do io
            JSON.print(io, Dict("a" => 1))
        end
        text = joinpath(tmp_dir, "t.txt")
        write(text, "hello\r\n")
        blob = joinpath(tmp_dir, "m.jls")
        open(blob, "w") do io
            Serialization.serialize(io, Dict("w" => 1))
        end
        _write_log(pipe, [
            _jl_node("j", payload, "json", String[]),
            _jl_node("t", text, "text", String[]),
            _jl_node("m", blob, "default", String[]),
        ], "build_log_20260101_000000_abc.json")
        @test read_node("j", pipeline_dir=pipe)["a"] == 1
        @test read_node("t", pipeline_dir=pipe) == "hello\r\n"
        # Note: ^ipc/^parquet branches are untested here because Arrow,
        # DataFrames, and Parquet2 are not test dependencies.
        # rds has no Julia reader.
        bad = joinpath(tmp_dir, "a.rds")
        write(bad, "x")
        _write_log(pipe, [_jl_node("r", bad, "rds", String[])],
            "build_log_20260102_000000_def.json")
        @test_throws ErrorException read_node("r", pipeline_dir=pipe, which_log="20260102")
        # pmml suggests return_path.
        pmml = joinpath(tmp_dir, "m.pmml")
        write(pmml, "<PMML/>")
        _write_log(pipe, [_jl_node("p", pmml, "pmml", String[])],
            "build_log_20260103_000000_ghi.json")
        err = try
            read_node("p", pipeline_dir=pipe, which_log="20260103")
            nothing
        catch e
            sprint(showerror, e)
        end
        @test occursin("return_path", err)
    end

    mktempdir() do tmp_dir
        pipe = joinpath(tmp_dir, "_pipeline")
        a = joinpath(tmp_dir, "a.txt"); write(a, "a")
        b = joinpath(tmp_dir, "b.txt"); write(b, "b")
        c = joinpath(tmp_dir, "c.txt"); write(c, "c")
        _write_log(pipe, [
            _jl_node("a", a, "text", String[]),
            _jl_node("b", b, "text", ["a"]),
            _jl_node("c", c, "text", ["b"]),
        ], "build_log_20260104_000000_jkl.json")
        @test sort(collect(keys(read_node_tree("a", pipeline_dir=pipe, which_log="20260104")))) == ["a", "b", "c"]
        @test sort(collect(keys(read_node_tree("c", pipeline_dir=pipe, which_log="20260104", include="parents")))) == ["a", "b", "c"]
        both = read_node_tree("b", pipeline_dir=pipe, which_log="20260104", include="both")
        @test both["b"] == "b"
        # Cycle terminates.
        _write_log(pipe, [
            _jl_node("a", a, "text", ["b"]),
            _jl_node("b", b, "text", ["a"]),
        ], "build_log_20260105_000000_mno.json")
        cyc = read_node_tree("a", pipeline_dir=pipe, which_log="20260105", include="both")
        @test sort(collect(keys(cyc))) == ["a", "b"]
        # Unknown dependency errors.
        _write_log(pipe, [_jl_node("a", a, "text", ["ghost"])],
            "build_log_20260106_000000_pqr.json")
        @test_throws ErrorException read_node_tree("a", pipeline_dir=pipe, which_log="20260106", include="parents")
        # Snapshot race: omit which_log so "latest" is used. The racing
        # deserializer writes a newer log that rewrites b to different
        # contents; the in-progress tree must keep the original contents.
        b_new = joinpath(tmp_dir, "b_new.txt"); write(b_new, "CHANGED")
        _write_log(pipe, [
            _jl_node("a", a, "text", String[]),
            _jl_node("b", b, "text", ["a"]),
        ], "build_log_20260108_000000_vwx.json")
        function racing(path)
            _write_log(pipe, [
                _jl_node("a", a, "text", String[]),
                _jl_node("b", b_new, "text", ["a"]),
                _jl_node("c", c, "text", ["b"]),
            ], "build_log_20260109_000000_zzz.json")
            return read(String(path), String)
        end
        tree = read_node_tree("a", pipeline_dir=pipe,
            deserializer=racing, include="children")
        @test sort(collect(keys(tree))) == ["a", "b"]
        @test tree["b"] == "b"
        # Unreadable fallback.
        pmml = joinpath(tmp_dir, "m.pmml"); write(pmml, "<PMML/>")
        _write_log(pipe, [
            _jl_node("good", a, "text", String[]),
            _jl_node("bad", pmml, "pmml", ["good"]),
        ], "build_log_20260110_000000_yza.json")
        @test_throws ErrorException read_node_tree("good", pipeline_dir=pipe, which_log="20260110")
        as_path = read_node_tree("good", pipeline_dir=pipe, which_log="20260110", on_unreadable="path")
        @test as_path["good"] == "a"
        @test endswith(as_path["bad"], "m.pmml")
        skipped = read_node_tree("good", pipeline_dir=pipe, which_log="20260110", on_unreadable="skip")
        @test sort(collect(keys(skipped))) == ["good"]
    end
end

@testset "inspect" begin
    mktempdir() do tmp_dir
        pipe = joinpath(tmp_dir, "_pipeline")
        art = joinpath(tmp_dir, "a.txt"); write(art, "a")
        _write_log(pipe, [
            _jl_node("a", art, "text", String[]),
            _jl_node("b", art, "json", ["a"]),
        ], "build_log_20260101_000000_abc.json")
        info = inspect_node("b", pipeline_dir=pipe)
        @test info["name"] == "b"
        @test info["serializer"] == "json"
        @test info["dependencies"] == ["a"]
        @test info["children"] == []
        @test info["error"] === nothing
        @test inspect_node("a", pipeline_dir=pipe)["children"] == ["b"]

        open(joinpath(pipe, "build_log_20260102_000000_def.json"), "w") do io
            JSON.print(io, Dict("nodes" => [
                _jl_node("a", art, "text", String[]),
                _jl_node("b", art, "text", ["a"]),
                _jl_node("c", art, "text", ["b"]),
            ]))
        end
        lin = lineage("b", pipeline_dir=pipe, which_log="20260102")
        @test lin["parents"] == ["a"] && lin["children"] == ["c"]

        # An R failure reads the same from Julia: plain VError JSON.
        verror = joinpath(tmp_dir, "err.json")
        open(verror, "w") do io
            JSON.print(io, Dict("type" => "VError", "code" => "RunError",
                "message" => "Error in lm.fit(x, y) : NA/NaN/Inf in 'y'",
                "context" => Dict("runtime" => "R")))
        end
        _write_log(pipe, [
            _jl_node("bad", verror, "default", String[]),
            _jl_node("good", art, "text", String[]),
        ], "build_log_20260103_000000_ghi.json")
        err_msg = error_msg("bad", pipeline_dir=pipe, which_log="20260103")
        @test occursin("lm.fit", err_msg)
        @test error_code("bad", pipeline_dir=pipe, which_log="20260103") == "RunError"
        @test_throws ErrorException error_msg("good", pipeline_dir=pipe, which_log="20260103")

        # warning_msg joins own and upstream warnings like T.
        parent_dir = joinpath(tmp_dir, "parent_art"); mkpath(parent_dir)
        write(joinpath(parent_dir, "artifact"), "x")
        open(joinpath(parent_dir, "warnings"), "w") do io
            JSON.print(io, ["stale column"])
        end
        child_dir = joinpath(tmp_dir, "child_art"); mkpath(child_dir)
        write(joinpath(child_dir, "artifact"), "x")
        open(joinpath(child_dir, "warnings"), "w") do io
            JSON.print(io, ["late column"])
        end
        open(joinpath(pipe, "build_log_20260104_000000_jkl.json"), "w") do io
            JSON.print(io, Dict("nodes" => [
                Dict("node" => "parent", "path" => joinpath(parent_dir, "artifact"),
                    "runtime" => "T", "serializer" => "text", "dependencies" => String[],
                    "status" => "Completed", "class" => "String", "warnings" => true),
                Dict("node" => "child", "path" => joinpath(child_dir, "artifact"),
                    "runtime" => "T", "serializer" => "text", "dependencies" => ["parent"],
                    "status" => "Completed", "class" => "String", "warnings" => true),
            ]))
        end
        @test warning_msg("child", pipeline_dir=pipe, which_log="20260104") ==
            "late column. Furthermore, Ancestor node 'parent' reported following warning: stale column"
        @test warning_msg("parent", pipeline_dir=pipe, which_log="20260104") == "stale column"
    end
end

@testset "inspect_pipeline" begin
    mktempdir() do tmp_dir
        pipe = joinpath(tmp_dir, "_pipeline")
        art = joinpath(tmp_dir, "a.txt"); write(art, "a")
        _write_log(pipe, [
            Dict("node" => "a", "path" => art, "runtime" => "T",
                "serializer" => "text", "dependencies" => String[],
                "status" => "Completed", "class" => "String"),
            Dict("node" => "b", "path" => art, "runtime" => "R",
                "serializer" => "json", "dependencies" => ["a"],
                "success" => true, "class" => "VDict"),
            Dict("node" => "c", "path" => art, "runtime" => "Python",
                "serializer" => "csv", "dependencies" => ["b"],
                "success" => "false", "class" => "DataFrame"),
        ], "build_log_20260101_000000_abc.json")
        rows = inspect_pipeline(pipeline_dir=pipe)
        @test [r["node"] for r in rows] == ["a", "b", "c"]
        @test rows[1]["status"] == "Completed"
        @test rows[2]["status"] == "Completed"
        @test rows[3]["status"] == "SoftFailed"
        @test rows[2]["dependencies"] == ["a"]

        other = joinpath(tmp_dir, "o.txt"); write(other, "o")
        _write_log(pipe, [
            Dict("node" => "a", "path" => other, "runtime" => "R",
                "serializer" => "text", "dependencies" => String[],
                "status" => "Completed", "class" => "String"),
        ], "build_log_20260102_000000_zzz.json")
        @test inspect_pipeline(pipeline_dir=pipe)[1]["runtime"] == "R"
        @test inspect_pipeline(pipeline_dir=pipe, which_log="20260101")[1]["runtime"] == "T"
    end

    mktempdir() do tmp_dir
        pipe = joinpath(tmp_dir, "_pipeline")
        mkpath(pipe)
        open(joinpath(pipe, "dag.json"), "w") do io
            JSON.print(io, [
                Dict("node_name" => "a", "depends" => String[]),
                Dict("node_name" => "b", "depends" => ["a"]),
            ])
        end
        rows = inspect_pipeline(pipeline_dir=pipe)
        @test [r["node"] for r in rows] == ["a", "b"]
        @test all(r -> r["status"] == "unbuilt", rows)
        @test rows[2]["dependencies"] == ["a"]
    end
end

@testset "frames" begin
    mktempdir() do tmp_dir
        pipe = joinpath(tmp_dir, "_pipeline")
        art = joinpath(tmp_dir, "a.txt"); write(art, "a")
        _write_log(pipe, [
            Dict("node" => "a", "path" => art, "runtime" => "T",
                "serializer" => "text", "dependencies" => String[],
                "status" => "Completed", "duration" => 1.5, "class" => "String"),
            Dict("node" => "b", "path" => art, "runtime" => "R",
                "serializer" => "json", "dependencies" => ["a"],
                "success" => true, "class" => "VDict"),
            Dict("node" => "c", "path" => art, "runtime" => "Python",
                "serializer" => "csv", "dependencies" => ["b"],
                "success" => "false", "class" => "DataFrame"),
        ], "build_log_20260101_000000_abc.json")
        rows = build_log_to_frame(pipeline_dir=pipe, which_log="20260101")
        @test [r["name"] for r in rows] == ["a", "b", "c"]
        @test rows[1]["duration"] == 1.5
        @test rows[3]["status"] == "SoftFailed"

        mkpath(joinpath(tmp_dir, "art"))
        artifact = joinpath(tmp_dir, "art", "artifact"); write(artifact, "x")
        open(joinpath(tmp_dir, "art", "warnings"), "w") do io
            JSON.print(io, ["late column", Dict("kind" => "NA", "message" => "3 NAs")])
        end
        _write_log(pipe, [
            Dict("node" => "bad", "path" => "/tmp/nonexistent",
                "runtime" => "T", "class" => "Error", "status" => "Errored",
                "error_code" => "NixError", "error_message" => "line1\nboom"),
            Dict("node" => "warned", "path" => artifact, "runtime" => "T",
                "class" => "DataFrame", "status" => "Completed", "warnings" => true),
        ], "build_log_20260103_000000_qqq.json")
        errs = collect_exceptions(pipeline_dir=pipe, which_log="20260103")
        @test sort([r["node"] for r in errs]) == ["bad", "warned", "warned"]
        bad = only([r for r in errs if r["node"] == "bad"])
        @test (bad["status"], bad["code"], bad["message"]) == ("Error", "NixError", "boom")

        open(joinpath(pipe, "build_log_20260104_000000_lll.json"), "w") do io
            JSON.print(io, Dict("pipeline" => "demo", "nodes" => []))
        end
        logs = list_logs(pipeline_dir=pipe)
        @test logs[1]["filename"] == "build_log_20260104_000000_lll.json"
        @test logs[1]["pipeline"] == "demo"
    end
end

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

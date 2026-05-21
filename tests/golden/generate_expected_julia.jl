#!/usr/bin/env julia

# Generate expected outputs using DataFrames.jl
# These are the "golden" results T should match for Julia parity

using DataFrames, CSV, Statistics

data_dir = "tests/golden/data"
output_dir = "tests/golden/expected"
mkpath(output_dir)
mkpath(data_dir)

println("Generating expected outputs from Julia...\n")

function save_output(df, name, operation)
    filepath = joinpath(output_dir, name * ".csv")
    CSV.write(filepath, df)
    println("✓ $operation: $name ($(nrow(df)) rows × $(ncol(df)) cols)")
end

simple_data = DataFrame(
    id = 1:10,
    name = ["Alice", "Bob", "Charlie", "David", "Eve",
            "Frank", "Grace", "Henry", "Iris", "Jack"],
    age = [25, 30, 35, 28, 22, 45, 33, 29, 31, 27],
    score = [85.5, 92.3, 78.9, 88.1, 95.0,
             82.4, 90.2, 76.5, 89.3, 91.7]
)

CSV.write(joinpath(data_dir, "julia_simple_data.csv"), simple_data)

# J.1 mutate
df_mutate = copy(simple_data)
df_mutate.age_plus_score = df_mutate.age .+ df_mutate.score
save_output(df_mutate, "julia_tidier_mutate", "Julia mutate")

# J.2 filter
df_filter = filter(row -> row.age > 30, simple_data)
save_output(df_filter, "julia_tidier_filter", "Julia filter")

# J.3 group by + summarize
df_group = copy(simple_data)
df_group.age_group = ifelse.(df_group.age .> 30, "old", "young")
df_summary = combine(
    groupby(df_group, :age_group),
    :score => mean => :mean_score,
    nrow => :count
)
sort!(df_summary, :age_group)
save_output(df_summary, "julia_tidier_groupby", "Julia group by + summarize")

# J.4 arrange
df_arrange = sort(copy(simple_data), :score, rev=true)
save_output(df_arrange, "julia_tidier_arrange", "Julia arrange")

println("\n✅ All Julia expected outputs generated!")

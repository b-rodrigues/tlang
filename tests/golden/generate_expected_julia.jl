#!/usr/bin/env julia

# Generate expected outputs using Tidier.jl
# These are the "golden" results T should match for Julia parity

using Pkg
# Ensure dependencies are available (slow but necessary if not in environment)
Pkg.activate(".")
Pkg.add(["DataFrames", "Tidier", "CSV"])

using DataFrames, Tidier, CSV

data_dir = "tests/golden/data"
output_dir = "tests/golden/expected"
mkpath(output_dir)

println("Generating expected outputs from Julia/Tidier...\n")

# Helper to save
function save_output(df, name, operation)
    filepath = joinpath(output_dir, name * ".csv")
    CSV.write(filepath, df)
    println("✓ $operation: $name ($(nrow(df)) rows × $(ncol(df)) cols)")
end

# Create dataset in Julia
simple_data = DataFrame(
    id = 1:10,
    name = ["Alice", "Bob", "Charlie", "David", "Eve", 
            "Frank", "Grace", "Henry", "Iris", "Jack"],
    age = [25, 30, 35, 28, 22, 45, 33, 29, 31, 27],
    score = [85.5, 92.3, 78.9, 88.1, 95.0, 
             82.4, 90.2, 76.5, 89.3, 91.7]
)

# Export this for T to use
CSV.write(joinpath(data_dir, "julia_simple_data.csv"), simple_data)

# Test J.1: Tidier Mutate
@chain simple_data begin
    @mutate(age_plus_score = age + score)
    save_output("julia_tidier_mutate", "Tidier @mutate")
end

# Test J.2: Tidier Filter
@chain simple_data begin
    @filter(age > 30)
    save_output("julia_tidier_filter", "Tidier @filter")
end

# Test J.3: Tidier Group By + Summarize
@chain simple_data begin
    @mutate(age_group = age > 30 ? "old" : "young")
    @group_by(age_group)
    @summarize(mean_score = mean(score), count = n())
    @arrange(age_group)
    save_output("julia_tidier_groupby", "Tidier @group_by + @summarize")
end

# Test J.4: Tidier Arrange
@chain simple_data begin
    @arrange(desc(score))
    save_output("julia_tidier_arrange", "Tidier @arrange")
end

println("\n✅ All Julia expected outputs generated!")

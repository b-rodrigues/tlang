-- ============================================================================
-- ARCHETYPICAL T-PIPELINE CHEATSHEET & EXAMPLE
-- ============================================================================
--
-- This file serves as a comprehensive reference guide to get you up to speed
-- with the T language pipeline syntax quickly.
--
-- Running / Building the Pipeline:
--   - From the Interactive T REPL: Build using `t_make()`
--   - From the CLI: Run using `t run src/pipeline.t`
--
-- For a comprehensive collection of complete, runnable, and real-world T projects,
-- please consult the official demos repository:
--   👉 https://github.com/b-rodrigues/t_demos
--
-- ============================================================================

-- 1. IMPORTING REUSABLE MODULES & HELPERS
-- You can import whole packages, specific functions, or other script files.
-- import my_math_utils
-- import data_cleaner[clean_nulls, impute_median]


-- 2. PIPELINE DEFINITION
-- A pipeline is declared using the `pipeline` keyword followed by a block of nodes.
-- Nodes within the pipeline can be written in native T, or run via external runtimes
-- (R, Python, Julia, Shell, Quarto).
--
-- Note: T automatically analyzes the raw code blocks and infers dependency order
-- by scanning the variables you reference!
p = pipeline {

  -- --------------------------------------------------------------------------
  -- A. Native T Node (Default)
  -- --------------------------------------------------------------------------
  -- If you omit the runtime, it defaults to native T. Bare assignments (like `x = 10`)
  -- are also automatically desugared into T nodes.
  -- Here we read raw data and serialize it for downstream polyglot nodes to consume.
  raw_data = node(
    command = read_csv("data/raw_dataset.csv", separator = ","),
    runtime = T,
    serializer = ^csv
  )


  -- --------------------------------------------------------------------------
  -- B. Python Node (pyn)
  -- --------------------------------------------------------------------------
  -- `pyn(...)` is a first-class shortcut for `node(runtime = Python, ...)`.
  -- Code inside `<{ ... }>` is passed verbatim to the target runtime.
  --
  -- Because `raw_data` is used in the raw code block below, the compiler
  -- automatically recognizes it as a dependency. When this node runs, the CSV 
  -- data from the `raw_data` node is deserialized and injected as a pandas DataFrame 
  -- variable named `raw_data`.
  python_processing = pyn(
    command = <{
import pandas as pd
# raw_data is already available as a pandas DataFrame
df = raw_data.copy()
df["scaled_value"] = df["value"] * 1.5

# The return value of the block is automatically serialized using the serializer
df
    }>,
    deserializer = ^csv,
    serializer = ^csv,
    env_vars = [MODEL_MODE: "production", THREADS: "4"] -- Inject Nix sandbox env variables!
  )


  -- --------------------------------------------------------------------------
  -- C. R Node (rn)
  -- --------------------------------------------------------------------------
  -- `rn(...)` is a convenience wrapper for `node(runtime = R, ...)`.
  -- We consume the result of `python_processing` (which is automatically loaded 
  -- as an R data.frame named `python_processing`).
  r_transformation = rn(
    command = <{
      library(dplyr)
      # python_processing is available as a data.frame
      result <- python_processing %>%
        filter(scaled_value > 10.0) %>%
        mutate(category = ifelse(scaled_value > 50.0, "High", "Low"))
      
      result
    }>,
    deserializer = ^csv,
    serializer = ^csv
  )


  -- --------------------------------------------------------------------------
  -- D. Julia Node (jln)
  -- --------------------------------------------------------------------------
  -- `jln(...)` is a convenience wrapper for `node(runtime = Julia, ...)`.
  -- We consume `r_transformation` (automatically loaded as a Julia DataFrame).
  -- Note: External packages like DataFrames and Statistics must be declared
  -- in your project's `tproject.toml` file under [jl-dependencies].
  julia_aggregation = jln(
    command = <{
      using DataFrames, Statistics
      
      # r_transformation is available as a DataFrame
      gdf = groupby(r_transformation, :category)
      summary_df = combine(gdf, :scaled_value => mean => :mean_scaled)
      
      summary_df
    }>,
    deserializer = ^csv,
    serializer = ^csv
  )


  -- --------------------------------------------------------------------------
  -- E. Shell Node (shn)
  -- --------------------------------------------------------------------------
  -- `shn(...)` is a convenience wrapper for `node(runtime = sh, ...)`.
  -- Useful for calling system utilities or command line tools (e.g. jq, awk, sed, curl).
  -- You can include static dependencies using the `include` field.
  shell_step = shn(
    command = <{
      echo "--- POST PROCESSING SHELL NODE ---"
      # We can read the serialized artifact directly from the workspace
      awk -F',' 'NR > 1 { print "Category: " $1 " | Mean: " $2 }' _artifacts/julia_aggregation.csv
    }>,
    include = ["data/raw_dataset.csv"]
  )


  -- --------------------------------------------------------------------------
  -- F. Quarto Rendering Node (qn)
  -- --------------------------------------------------------------------------
  -- `qn(...)` is a wrapper for `node(runtime = Quarto, ...)`.
  -- Points directly to an external file using `script = ...` (mutually exclusive with `command`).
  -- Perfect for compiling reports, documents, or presentations.
  report = qn(
    script = "src/report.qmd"
  )
}


-- ============================================================================
-- 3. PIPELINE ORCHESTRATION & ERROR HANDLING
-- ============================================================================

-- Build the pipeline. `verbose` accepts integers 0 (quiet) up to 3 (extremely verbose).
-- The builder resolves dependencies, compiles the Nix derivation sandbox, and runs the steps.
--
-- Note: When running your own pipelines, you can build them using `t_make()`
-- from the interactive T REPL, or by executing `t run src/pipeline.t` from the CLI.
res = build_pipeline(p, verbose = 1)

-- Check if the build failed and print execution logs for debugging
if (is_error(res)) {
  print("🚨 PIPELINE BUILD FAILED!")
  -- Retrieve and print the raw stderr log of the failed node (e.g. julia_aggregation)
  print(read_log("julia_aggregation"))
  exit(1)
}

-- ============================================================================
-- 4. RETRIEVING, EXPORTING & INSPECTING PIPELINE OUTPUTS & METADATA
-- ============================================================================

-- A. read_node("node_name")
-- Reads the built/materialized node artifact from the latest build directory.
final_data = read_node("julia_aggregation")

-- B. read_node(p, "node_name")
-- Reads both the actual value AND structured execution diagnostics for an in-memory pipeline.
node_info = read_node(p, "julia_aggregation")
-- print(node_info.v)          -- The deserialized data value
-- print(node_info.diagnostics) -- Node execution warnings, runtime, or exit codes

-- C. read_pipeline(p)
-- Returns a dictionary containing all computed node values, names, and aggregated pipeline diagnostics.
pipeline_metadata = read_pipeline(p)

-- D. pipeline_to_frame(p)
-- Converts the pipeline structure into a DataFrame where each row represents a node.
-- Handy for debugging large pipelines! Columns: name, runtime, serializer, deps, depth, etc.
pipeline_df = pipeline_to_frame(p)

-- E. pipeline_nodes(p) & pipeline_deps(p)
-- List node names or extract the dependency DAG:
names = pipeline_nodes(p)
deps  = pipeline_deps(p)

-- F. pipeline_copy()
-- Copies all computed node artifacts from the Nix store to a local directory for easy access.
-- By default, it copies all nodes from the latest build to the "pipeline-output/" folder.
-- You can specify a custom folder using the `target_dir` argument:
pipeline_copy(target_dir = "pipeline-outputs")

-- Print the results in the REPL / standard out
print("🎉 Pipeline completed successfully!")
print("Aggregated Results:")
print(final_data)

-- Write out the finalized artifact to your output directory
write_csv(final_data, "outputs/final_summary.csv")

-- tests/pipeline/multi_lang_pipeline.t
--
-- This script demonstrates a multi-language pipeline using T, R, and Python.
-- It satisfies the user request to use the node() function with different runtimes
-- and custom CSV serializers/deserializers.

-- 1. Define T helper functions for CSV I/O
-- These are used when a T node needs to read/write CSV instead of the default .tobj
t_write_csv = \(df, path) write_csv(df, path)
t_read_csv = \(path) read_csv(path)

-- Note: We assume that r_read_csv, r_write_csv, py_read_csv, and py_write_csv
-- are available in their respective language environments (e.g., provided via
-- the 'functions' argument or as part of a shared library).

p = pipeline {
    -- NODE 1: T Language
    -- Load raw mtcars data and serialize it as CSV for other languages to consume.
    raw_data = node(
        command = read_csv("tests/pipeline/data/mtcars.csv", separator = "|"),
        runtime = T,
        serializer = t_write_csv
    )

    -- NODE 2: R Language (using dplyr)
    -- We use backticks to ensure 'cyl' and 'mpg' are unparsed without the '$' prefix
    -- which would be invalid in R's dplyr context.
    -- We depend on raw_data (T node), so we use a CSV deserializer for R.
    summary_r = node(
        command = raw_data |> group_by(`cyl`) |> summarize(avg_mpg = mean(`mpg`)),
        runtime = R,
        deserializer = r_read_csv,
        serializer = r_write_csv,
        functions = "tests/pipeline/iolib.R"
    )

    -- NODE 3: Python Language (using pandas)
    -- Similar to R, we use a custom CSV deserializer/serializer.
    -- Python's pandas can use dot access for columns if the names are simple.
    summary_py = node(
        command = raw_data.groupby("cyl").mean(),
        runtime = Python,
        deserializer = py_read_csv,
        serializer = py_write_csv,
        functions = "tests/pipeline/iolib.py"
    )

    -- NODE 4: T Language
    -- Collect and combine results from R and Python.
    -- We need to use t_read_csv since the upstream nodes wrote CSV.
    final_results = node(
        command = [r_part: summary_r, py_part: summary_py],
        runtime = T,
        deserializer = t_read_csv
    )
}

-- Build the pipeline
build_pipeline(p)

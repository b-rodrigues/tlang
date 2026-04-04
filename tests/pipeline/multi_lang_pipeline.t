-- tests/pipeline/multi_lang_pipeline.t
--
-- This script demonstrates a multi-language pipeline using T, R, and Python.
-- It satisfies the user request to use the node() function with different runtimes
-- and custom CSV serializers/deserializers.

-- Note: t_write_csv and t_read_csv are defined in iolib.t and loaded via
-- the 'functions' argument, just like iolib.R and iolib.py for R and Python.

p = pipeline {
    -- NODE 1: T Language
    -- Load raw mtcars data and serialize it as CSV for other languages to consume.
    raw_data = node(
        command = read_csv("tests/pipeline/data/mtcars.csv", separator = "|"),
        runtime = T,
        serializer = "csv"
    )

    -- NODE 2: R Language (using dplyr)
    -- The <{ ... }> raw code block passes R code verbatim without T parsing.
    -- Dependencies (raw_data) are auto-detected from identifiers in the block.
    summary_r = node(
        command = <{ raw_data |> dplyr::group_by(cyl) |> dplyr::summarize(avg_mpg = mean(mpg)) }>,
        runtime = R,
        deserializer = "csv",
        serializer = "csv"
    )

    -- NODE 3: Python Language (using pandas)
    summary_py = node(
        command = <{ raw_data.groupby("cyl").mean() }>,
        runtime = Python,
        deserializer = "csv",
        serializer = "csv"
    )

    -- NODE 4: T Language
    -- Collect and combine results from R and Python.
    final_results = node(
        command = [r_part: summary_r, py_part: summary_py],
        runtime = T,
        deserializer = [ summary_py: "csv", summary_r: "csv" ]
    )
}

-- Build the pipeline
build_pipeline(p, verbose=1)


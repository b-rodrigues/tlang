-- tests/pipeline/polyglot_shell_pipeline.t
--
-- End-to-end polyglot pipeline using T, R, Python, and sh.
-- The shell node reads upstream artifacts through the exported T_NODE_* paths
-- and emits a plain-text report that can be inspected after the build.

p = pipeline {
    raw_data = node(
        command = read_csv("tests/pipeline/data/mtcars.csv", separator = "|"),
        runtime = T,
        serializer = "^csv",
        functions = "tests/pipeline/iolib.t"
    )

    summary_r = rn(
        command = <{ raw_data |> dplyr::group_by(cyl) |> dplyr::summarize(avg_mpg = mean(mpg)) }>,
        serializer = "^csv",
        deserializer = "^csv",
        functions = "tests/pipeline/iolib.R"
    )

    summary_py = pyn(
        command = <{ summary_py = raw_data.groupby("cyl").agg({"mpg": "mean"}).reset_index().rename(columns={"mpg": "avg_mpg"}) }>,
        serializer = "^csv",
        deserializer = "^csv",
        functions = "tests/pipeline/iolib.py"
    )

    shell_report = shn(
        command = <{
#!/bin/sh
set -eu

# Dependencies for T's lexical pipeline analysis: raw_data summary_r summary_py
printf 'Polyglot summary report\n'
printf 'raw_data artifact: %s\n' "$T_NODE_raw_data/artifact"
printf '\nR summary\n'
cat "$T_NODE_summary_r/artifact"
printf '\nPython summary\n'
cat "$T_NODE_summary_py/artifact"
        }>
    )
}

build_pipeline(p, verbose=1)

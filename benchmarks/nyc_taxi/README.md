# NYC Taxi benchmark

This directory contains a reproducible benchmark scaffold for comparing:

- **T**
- **Python** (`pyarrow` + `pandas`)
- **R** (`arrow` + `dplyr`)

against the NYC Taxi yellow-cab dataset.

## Layout

```text
benchmarks/nyc_taxi/
  README.md
  dataset.md
  prepare_dataset.sh
  queries/
  python/
  r/
  run_benchmark.sh
  results/
```

## Current T limitation

T does not yet expose `open_dataset()` / Parquet dataset primitives in the runtime.
The benchmark therefore keeps the Python and R baselines on the partitioned Parquet
dataset, while the T scripts benchmark the **full-materialization** path via a
prepared single-file input.

That still makes the benchmark useful for the spec's intended comparison:

- **Python/R**: dataset scan + filter pushdown against partitioned Parquet
- **T**: materialized single-file execution, preferring `read_arrow()` when an Arrow IPC cache is available and falling back to `read_csv()`

## Prerequisites

Use the repository flake:

```bash
nix develop
```

The flake already provides:

- `t`
- `python` with `pandas` and `pyarrow`
- `Rscript` with `arrow` and `dplyr`

Both helper scripts automatically re-enter `nix develop` when `nix` is available.

## Prepare the dataset

Example subset:

```bash
./benchmarks/nyc_taxi/prepare_dataset.sh \
  --months 2023-01,2023-02,2023-03 \
  --clean \
  --raw-dir /tmp/nyc-taxi-raw \
  --parquet-dir /tmp/nyc-taxi-parquet \
  --materialized-csv /tmp/nyc-taxi-materialized.csv
```

The preparation script:

1. discovers and downloads monthly TLC yellow-trip files from the official NYC TLC trip-records page
2. adds `year` and `month` columns when needed
3. writes a Hive-partitioned Parquet dataset
4. optionally appends the same data to a single materialized CSV file for T
5. and, when the benchmark runner executes, caches a sibling Arrow IPC file so T can load it through `read_arrow()`

For safety, `prepare_dataset.sh` refuses to write into a non-empty Parquet output
directory unless you pass `--clean`.

See [`dataset.md`](dataset.md) for more details.

## Run the benchmark

```bash
./benchmarks/nyc_taxi/run_benchmark.sh \
  --months 2023-01,2023-02,2023-03 \
  --parquet-dir /tmp/nyc-taxi-parquet \
  --csv-path /tmp/nyc-taxi-materialized.csv \
  --iterations 3
```

If the Parquet dataset is missing, the runner now calls `prepare_dataset.sh`
non-interactively to download and build it before benchmarking. If only the
materialized CSV is missing, the runner regenerates it from the existing Parquet
dataset. The runner also caches a sibling `.arrow` IPC file next to the CSV and
passes both paths to the T scripts; those scripts prefer `read_arrow()` when the
Arrow cache is present. Use `--months` to control which monthly TLC files are
downloaded during that automatic preparation step.

The runner writes results to:

```text
benchmarks/nyc_taxi/results/results.csv
```

## Recorded metrics

Each run records:

- `engine`
- `query`
- `iteration`
- `time_sec`
- `memory_mb`
- `rows_scanned`
- `rows_returned`
- `status`

`rows_scanned` is currently reported as `NA` for the Parquet-backed Python and R
scripts so the benchmark does not perform an extra full-dataset pass just to count
rows. The T scripts report the loaded single-file row count after `read_arrow()`
or `read_csv()`, depending on which benchmark input is available.

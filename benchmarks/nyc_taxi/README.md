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
prepared CSV file.

That still makes the benchmark useful for the spec's intended comparison:

- **Python/R**: dataset scan + filter pushdown against partitioned Parquet
- **T**: materialized CSV execution with `read_csv() |> filter() |> group_by() |> summarize()`

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

1. downloads monthly TLC CSV files
2. adds `year` and `month` columns when needed
3. writes a Hive-partitioned Parquet dataset
4. optionally appends the same data to a single materialized CSV file for T

For safety, `prepare_dataset.sh` refuses to write into a non-empty Parquet output
directory unless you pass `--clean`.

See [`dataset.md`](dataset.md) for more details.

## Run the benchmark

```bash
./benchmarks/nyc_taxi/run_benchmark.sh \
  --parquet-dir /tmp/nyc-taxi-parquet \
  --csv-path /tmp/nyc-taxi-materialized.csv \
  --iterations 3
```

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
rows. The T scripts still report the materialized CSV row count after `read_csv()`.

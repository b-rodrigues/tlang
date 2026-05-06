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

## Benchmark Setup

T now supports native **Parquet** ingestion via `read_parquet()`, allowing a direct head-to-head comparison with Python and R using the same binary format.

- **Python**: `pyarrow` + `pandas` scanning partitioned Parquet.
- **R**: `arrow` + `dplyr` scanning partitioned Parquet.
- **T**: Materialized Parquet or CSV execution with native Arrow-backed readers.

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

## Query catalogue

The benchmark runner supports these query ids:

- `q1` — long trips filter + summarize
- `q2` — group by passenger count
- `q3` — monthly grouped stats
- `q4` — high-cardinality grouping by `PULocationID`
- `q5` — composite grouping by `PULocationID` and `DOLocationID`
- `q6` — vectorized tip-percent mutation
- `q7` — monthly `n_distinct(PULocationID)`
- `q8` — full-table sort by `total_amount` descending
- `q9` — chained numeric/categorical filters
- `q10` — monthly revenue pivoted wide by vendor
- `q11` — heavy grouped summarize with multiple aggregates
- `q12` — filter + mutate + grouped rollup + sort
- `q13` — high-cardinality grouped rollup with multiple aggregates
- `q14` — core `select()` baseline on 100k rows
- `q15` — core `filter()` baseline on 100k rows
- `q16` — core `mutate()` baseline on 100k rows
- `q17` — core `select()` baseline on 1M rows (reuses `q14` scripts)
- `q18` — core `filter()` baseline on 1M rows (reuses `q15` scripts)
- `q19` — core `mutate()` baseline on 1M rows (reuses `q16` scripts)
- `q20` — nesting/unnesting of dataframes

By default, `run_benchmark.sh` runs the full `q1`-`q20` suite. Use `--queries`
to run a subset when you only want a faster smoke benchmark.

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
dataset. Use `--months` to control which monthly TLC files are downloaded during
that automatic preparation step.

To run only specific scenarios:

```bash
./benchmarks/nyc_taxi/run_benchmark.sh \
  --months 2023-01 \
  --queries q4,q5,q6,q11 \
  --iterations 1
```

The runner writes results to:

```text
benchmarks/nyc_taxi/results/results.csv
```

The `q14`-`q19` scenarios are the fixed-size large-dataset baselines referenced in
`spec_files/path-to-0.52.0.md` for `v0.51.1 — Alpha Hardening & Performance`.
When any of those queries are selected, the runner automatically materializes
100k-row and 1M-row CSV/Parquet subsets from the benchmark dataset before timing
the core verbs.

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

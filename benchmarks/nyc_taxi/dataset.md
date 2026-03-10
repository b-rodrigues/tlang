# Dataset preparation notes

## Source

The benchmark uses the NYC Taxi and Limousine Commission yellow-trip monthly files.

Official source page:

```text
https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page
```

`prepare_dataset.sh` discovers monthly `yellow_tripdata_YYYY-MM` download links
from that official TLC page and downloads whichever file format is published
there (currently parquet, historically CSV).

## Recommended sizes

- **CI / smoke benchmark**: 1-3 months
- **Developer benchmark**: 6-12 months
- **Full benchmark**: multiple years, depending on available disk and RAM

## Storage expectations

You should plan for:

- the raw CSV downloads
- the partitioned Parquet dataset
- an optional materialized CSV file for the current T benchmark path
- an optional Arrow IPC cache derived from that CSV for repeated T benchmark runs

For large runs, this can easily require tens of gigabytes of disk space.

## Partitioning

`prepare_dataset.sh` writes Parquet with Hive-style partition directories:

```text
.../nyc_taxi_parquet/year=2023/month=1/...
```

The preparation step ensures `year` and `month` columns exist before the Parquet
dataset is written.

## T benchmark input

Until T grows a native `open_dataset()` / Parquet dataset API, the T query scripts
consume a single-file materialization via the `NYC_TAXI_CSV` environment variable,
and prefer a sibling Arrow IPC cache via `NYC_TAXI_ARROW` when it exists.

The preparation script can generate that materialized CSV incrementally while it is
building the Parquet dataset:

```bash
./benchmarks/nyc_taxi/prepare_dataset.sh \
  --months 2023-01,2023-02 \
  --materialized-csv /tmp/nyc-taxi-materialized.csv
```

If you already have a suitable CSV file, pass it directly to the benchmark runner
with `--csv-path`. The runner will derive a sibling `.arrow` path from that CSV
location and cache an Arrow IPC file there for `read_arrow()` when needed.

`run_benchmark.sh` can also prepare these inputs automatically: it downloads and
builds the Parquet dataset when it is missing, and if only the materialized CSV
is missing it regenerates that CSV from the existing Parquet dataset. After that,
it creates or refreshes the sibling Arrow IPC cache before running the T queries.

If you rerun preparation into the same Parquet directory, pass `--clean` first.
Without it, `prepare_dataset.sh` stops instead of appending duplicate data files to
existing partitions.

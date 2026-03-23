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
consume a single CSV file via the `NYC_TAXI_CSV` environment variable.

The preparation script can generate that materialized CSV incrementally while it is
building the Parquet dataset:

```bash
./benchmarks/nyc_taxi/prepare_dataset.sh \
  --months 2023-01,2023-02 \
  --materialized-csv /tmp/nyc-taxi-materialized.csv
```

If you already have a suitable CSV file, pass it directly to the benchmark runner
with `--csv-path`.

`run_benchmark.sh` can also prepare these inputs automatically: it downloads and
builds the Parquet dataset when it is missing, and if only the materialized CSV
is missing it regenerates that CSV from the existing Parquet dataset.

When the core-verb benchmark queries (`q14`-`q19`) are selected, the runner also
derives fixed-size 100k-row and 1M-row materialized CSV/Parquet files from the
full materialized Parquet input so the roadmap baseline measurements run against
exact row counts.

If you rerun preparation into the same Parquet directory, pass `--clean` first.
Without it, `prepare_dataset.sh` stops instead of appending duplicate data files to
existing partitions.

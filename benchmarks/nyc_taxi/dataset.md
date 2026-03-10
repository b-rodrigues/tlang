# Dataset preparation notes

## Source

The benchmark uses the NYC Taxi and Limousine Commission yellow-trip monthly files.

Default URL pattern:

```text
https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_YYYY-MM.csv
```

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

If you rerun preparation into the same Parquet directory, pass `--clean` first.
Without it, `prepare_dataset.sh` stops instead of appending duplicate data files to
existing partitions.

# 1. Benchmark goals

Add reproducible benchmarks that measure:

1. dataset scan performance
2. filter + aggregation performance
3. grouped aggregations
4. streaming vs full materialization

The benchmarks should compare:

* T
* Python (pyarrow + pandas)
* R (arrow + dplyr)

Dataset: NYC Taxi (~20–50GB).

Published by
NYC Taxi and Limousine Commission.

---

# 2. Repository structure

Add a `benchmarks/` directory.

```
benchmarks/
  nyc_taxi/
    README.md
    dataset.md
    prepare_dataset.sh

    queries/
      q1_long_trips.t
      q2_group_passenger.t
      q3_monthly_stats.t

    python/
      q1_long_trips.py
      q2_group_passenger.py
      q3_monthly_stats.py

    r/
      q1_long_trips.R
      q2_group_passenger.R
      q3_monthly_stats.R

    run_benchmark.sh
    results/
```

The benchmark should use the repository's flake to get access to the tools it'll need.

---

# 3. Dataset preparation

Script to download and convert dataset to parquet.

```
benchmarks/nyc_taxi/prepare_dataset.sh
```

Steps:

1. download monthly CSV files
2. convert to parquet
3. partition by year/month

Example:

```bash
mkdir nyc_taxi_parquet

python convert.py
```

Conversion script uses Arrow:

```python
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

df = pd.read_csv("yellow_tripdata_2023-01.csv")

table = pa.Table.from_pandas(df)

pq.write_to_dataset(
    table,
    root_path="nyc_taxi_parquet",
    partition_cols=["year", "month"]
)
```

---

# 4. Benchmark queries

Define **3 canonical queries**.

## Query 1: long trip statistics

Filter + aggregation.

Pseudo-T:

```
ds = open_dataset("nyc_taxi")

result =
  ds
  |> filter(trip_distance > 10)
  |> summarize(
       avg_fare = mean(fare_amount),
       trips = count()
     )
```

Measures:

* scan speed
* filter pushdown
* aggregation

---

## Query 2: passenger group statistics

Grouped aggregation.

```
ds
|> group_by(passenger_count)
|> summarize(
     avg_fare = mean(fare_amount),
     trips = count()
   )
```

Measures:

* grouping performance
* column scanning efficiency

---

## Query 3: monthly statistics

Grouped aggregation with partitions.

```
ds
|> filter(trip_distance > 5)
|> group_by(year, month)
|> summarize(
     avg_fare = mean(fare_amount),
     trips = count()
   )
```

Measures:

* partition pruning
* multi-column grouping

---

# 5. Python baseline implementation

Example benchmark script.

```
benchmarks/nyc_taxi/python/q1_long_trips.py
```

```python
import time
import pyarrow.dataset as ds
import pyarrow.compute as pc

start = time.time()

dataset = ds.dataset("nyc_taxi_parquet", partitioning="hive")

table = dataset.to_table(
    filter=pc.field("trip_distance") > 10,
    columns=["trip_distance", "fare_amount"]
)

df = table.to_pandas()

result = df["fare_amount"].mean()

print("avg fare:", result)
print("time:", time.time() - start)
```

---

# 6. R baseline implementation

```
benchmarks/nyc_taxi/r/q1_long_trips.R
```

```r
library(arrow)
library(dplyr)

start <- Sys.time()

ds <- open_dataset("nyc_taxi_parquet")

result <- ds |>
  filter(trip_distance > 10) |>
  summarise(avg_fare = mean(fare_amount)) |>
  collect()

print(result)

print(Sys.time() - start)
```

---

# 7. T implementation

Add dataset primitives to T:

Required runtime functionality:

```
open_dataset(path)
filter()
group_by()
summarize()
collect()
```

Example T script:

```
ds = open_dataset("nyc_taxi_parquet")

result =
  ds
  |> filter(trip_distance > 10)
  |> summarize(avg_fare = mean(fare_amount))

print(result)
```

---

# 8. Benchmark runner

Single runner script.

```
benchmarks/nyc_taxi/run_benchmark.sh
```

Example:

```bash
echo "Running Python benchmark"
python python/q1_long_trips.py

echo "Running R benchmark"
Rscript r/q1_long_trips.R

echo "Running T benchmark"
t queries/q1_long_trips.t
```

Collect results into:

```
results/results.csv
```

---

# 9. Metrics collected

Each run records:

* runtime
* peak memory
* rows scanned
* rows returned

Example CSV:

```
engine,query,time_sec,memory_mb
python,q1,4.3,780
r,q1,4.9,810
t,q1,2.1,320
```

---

# 10. CI integration

Dataset too large for CI.

Strategy:

CI runs:

* **small subset (~5GB)**

Full benchmark:

* nightly job
* dedicated runner

---

# 11. Future benchmark extensions

Add more workloads:

### joins

Taxi + weather datasets.

### window functions

```
rank()
rolling_mean()
```

### streaming aggregation

Batch processing.

### wide table scans

Column selection tests.

---

# 12. Success criteria

The benchmark should verify that T:

* matches Arrow scan performance
* outperforms pandas/dplyr pipelines
* scales to **multi-GB datasets**


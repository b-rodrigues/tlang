# Stress-Testing Arrow-Backed Operations in T

This document outlines additional query scenarios for the NYC Taxi benchmark to stress-test the performance of the T language's Arrow-backed operations.

## Current Benchmarks
1. **q1_long_trips**: Filtering (`trip_distance > 10`) + simple `summarize` (`mean`, `nrow`).
2. **q2_group_passenger**: Single-column `group_by` (`passenger_count`) + simple `summarize` (`mean`, `n()`).
3. **q3_monthly_stats**: Filtering + two-column `group_by` (`year`, `month`) + `summarize`.

## Proposed High-Stress Scenarios

### 1. High-Cardinality Grouping
Grouping by columns with a large number of unique values stresses the hash-aggregation performance and group-by indices reconstruction.
*   **Query**: Group by `PULocationID` (Pickup Location ID, ~260 unique values) or `DOLocationID`.
*   **Stress Point**: Hash table performance for group identification and memory usage for partitioning.
*   **T Implementation**:
    ```t
    df |> group_by($PULocationID) |> summarize($avg_fare = mean($fare_amount), $trips = n())
    ```

### 2. Multi-Column Composite Grouping
*   **Query**: Group by `PULocationID` and `DOLocationID` simultaneously.
*   **Stress Point**: Cartesian product of keys; testing how efficiently T handles composite keys in grouped operations.
*   **T Implementation**:
    ```t
    df |> group_by($PULocationID, $DOLocationID) |> summarize($avg_tip = mean($tip_amount))
    ```

### 3. Vectorized Mutation (Arithmetic Stress)
Testing element-wise operations between columns.
*   **Query**: Create a new column `tip_percent = tip_amount / total_amount * 100`.
*   **Stress Point**: Loop performance in `Arrow_compute.column_binary_op` for large arrays.
*   **T Implementation**:
    ```t
    df |> mutate($tip_percent = $tip_amount / $total_amount * 100)
    ```

### 4. Distinct Count (n_distinct)
*   **Query**: Count unique `PULocationID` per month.
*   **Stress Point**: Performance of `Arrow_compute.count_distinct_column` which uses a hash set internally.
*   **T Implementation**:
    ```t
    df |> group_by($month) |> summarize($unique_pickups = n_distinct($PULocationID))
    ```

### 5. Large-Scale Sorting (Arrange)
*   **Query**: Sort the whole dataset by `total_amount` descending.
*   **Stress Point**: Memory access patterns during global row reordering.
*   **T Implementation**:
    ```t
    df |> arrange(desc($total_amount))
    ```

### 6. Complex Chain of Filters
*   **Query**: Multiple AND conditions involving numeric and categorical-like filters.
*   **Stress Point**: Mask generation and application across multiple columns.
*   **T Implementation**:
    ```t
    df |> filter($passenger_count > 1 & $trip_distance > 5 & $payment_type == 1)
    ```

### 7. Pivot Operations (If supported natively)
*   **Query**: `pivot_wider` monthly revenue per `VendorID`.
*   **Stress Point**: Structural transformation of the table layout.
*   **T Implementation**:
    ```t
    df |> group_by($year, $month, $VendorID) 
       |> summarize($rev = sum($total_amount))
       |> pivot_wider(names_from = $VendorID, values_from = $rev)
    ```

### 8. Heavy Summarize (Many Aggregates)
*   **Query**: Calculate 10+ different aggregates in one go.
*   **Stress Point**: Efficiency of processing multiple aggregation kernels on the same table slices.
*   **T Implementation**:
    ```t
    df |> group_by($VendorID) |> summarize(
      $mean_fare = mean($fare_amount),
      $mean_tip = mean($tip_amount),
      $total_rev = sum($total_amount),
      $max_dist = max($trip_distance),
      $min_dist = min($trip_distance),
      $total_passengers = sum($passenger_count),
      $trips = n(),
      $unique_locs = n_distinct($PULocationID)
    )
    ```

## Performance Metrics to Monitor
- **Execution Time (sec)**: How long each engine takes.
- **Peak Memory (MB)**: Memory overhead of group-by indices and intermediate vectors.
- **Throughput (rows/sec)**: Efficiency of the compute kernels.
- **Serialization Overhead**: Cost of `read_parquet()` vs `read_csv()`.

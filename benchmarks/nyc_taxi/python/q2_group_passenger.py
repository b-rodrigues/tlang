import argparse
import time

import pyarrow.dataset as ds


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, help="Path to the partitioned parquet dataset")
    args = parser.parse_args()

    started = time.perf_counter()
    dataset = ds.dataset(args.dataset, format="parquet", partitioning="hive")
    rows_scanned = dataset.count_rows()

    table = dataset.to_table(columns=["passenger_count", "fare_amount"])
    frame = table.to_pandas()
    result = (
        frame.groupby("passenger_count", dropna=False)
        .agg(avg_fare=("fare_amount", "mean"), trips=("fare_amount", "size"))
        .reset_index()
    )

    print(result)
    print(f"ROWS_SCANNED={rows_scanned}")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

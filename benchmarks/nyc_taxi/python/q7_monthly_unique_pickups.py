import argparse
import time

import pyarrow.dataset as ds


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, help="Path to the partitioned parquet dataset")
    args = parser.parse_args()

    started = time.perf_counter()
    dataset = ds.dataset(args.dataset, format="parquet", partitioning="hive")

    table = dataset.to_table(columns=["month", "PULocationID"])
    frame = table.to_pandas()
    result = (
        frame.groupby("month", dropna=False)
        .agg(unique_pickups=("PULocationID", "nunique"))
        .reset_index()
        .sort_values("month")
    )

    print(result.head(10))
    print("ROWS_SCANNED=NA")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

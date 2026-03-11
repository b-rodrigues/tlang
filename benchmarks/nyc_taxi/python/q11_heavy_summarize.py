import argparse
import time

import pyarrow.dataset as ds


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, help="Path to the partitioned parquet dataset")
    args = parser.parse_args()

    started = time.perf_counter()
    dataset = ds.dataset(args.dataset, format="parquet", partitioning="hive")

    table = dataset.to_table(
        columns=[
            "VendorID",
            "fare_amount",
            "tip_amount",
            "total_amount",
            "trip_distance",
            "passenger_count",
            "PULocationID",
        ]
    )
    frame = table.to_pandas()
    frame = frame[frame["trip_distance"].notna()]
    result = (
        frame.groupby("VendorID", dropna=False)
        .agg(
            mean_fare=("fare_amount", "mean"),
            mean_tip=("tip_amount", "mean"),
            total_rev=("total_amount", "sum"),
            max_dist=("trip_distance", "max"),
            min_dist=("trip_distance", "min"),
            total_passengers=("passenger_count", "sum"),
            trips=("VendorID", "size"),
            unique_locs=("PULocationID", "nunique"),
        )
        .reset_index()
        .sort_values("VendorID")
    )

    print(result.head(10))
    print("ROWS_SCANNED=NA")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

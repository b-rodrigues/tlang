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
            "year",
            "month",
            "VendorID",
            "payment_type",
            "PULocationID",
            "trip_distance",
            "fare_amount",
            "tip_amount",
            "total_amount",
        ]
    )
    frame = table.to_pandas()
    frame = frame[
        frame["trip_distance"].notna()
        & frame["fare_amount"].notna()
        & (frame["trip_distance"] > 0)
        & (frame["total_amount"] > 0)
    ].copy()
    frame["fare_per_mile"] = frame["fare_amount"] / frame["trip_distance"]
    frame["tip_percent"] = (frame["tip_amount"] / frame["total_amount"]) * 100.0
    result = (
        frame.groupby(["year", "month", "VendorID", "payment_type"], dropna=False)
        .agg(
            avg_fare_per_mile=("fare_per_mile", "mean"),
            avg_tip_percent=("tip_percent", "mean"),
            total_revenue=("total_amount", "sum"),
            max_trip_distance=("trip_distance", "max"),
            rides=("VendorID", "size"),
            unique_pickups=("PULocationID", "nunique"),
        )
        .reset_index()
        .sort_values("total_revenue", ascending=False)
    )

    print(result.head(10))
    print("ROWS_SCANNED=NA")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

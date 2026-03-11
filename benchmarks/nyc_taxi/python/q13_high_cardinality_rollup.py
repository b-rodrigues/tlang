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
            "RatecodeID",
            "PULocationID",
            "DOLocationID",
            "passenger_count",
            "fare_amount",
            "tip_amount",
            "total_amount",
            "tolls_amount",
        ]
    )
    frame = table.to_pandas()
    frame = frame[
        frame["fare_amount"].notna() & frame["tip_amount"].notna() & (frame["total_amount"] > 0)
    ]
    result = (
        frame.groupby(["VendorID", "RatecodeID", "PULocationID", "DOLocationID"], dropna=False)
        .agg(
            avg_fare=("fare_amount", "mean"),
            avg_tip=("tip_amount", "mean"),
            avg_total=("total_amount", "mean"),
            total_tolls=("tolls_amount", "sum"),
            trips=("VendorID", "size"),
            max_passengers=("passenger_count", "max"),
        )
        .reset_index()
        .sort_values("trips", ascending=False)
    )

    print(result.head(10))
    print("ROWS_SCANNED=NA")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

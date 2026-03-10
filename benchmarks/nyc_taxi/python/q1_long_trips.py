import argparse
import time

import pyarrow.compute as pc
import pyarrow.dataset as ds


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, help="Path to the partitioned parquet dataset")
    args = parser.parse_args()

    started = time.perf_counter()
    dataset = ds.dataset(args.dataset, format="parquet", partitioning="hive")

    table = dataset.to_table(
        filter=pc.field("trip_distance") > 10,
        columns=["fare_amount"],
    )
    frame = table.to_pandas()
    avg_fare = frame["fare_amount"].mean()
    rows_returned = 1

    print(f"avg_fare={avg_fare}")
    print("ROWS_SCANNED=NA")
    print(f"ROWS_RETURNED={rows_returned}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

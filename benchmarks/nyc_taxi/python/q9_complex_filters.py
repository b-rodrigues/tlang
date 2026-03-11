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
        filter=(
            (pc.field("passenger_count") > 1)
            & (pc.field("trip_distance") > 5)
            & (pc.field("payment_type") == 1)
        ),
    )
    result = table.to_pandas()

    print(result.head(10))
    print("ROWS_SCANNED=NA")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

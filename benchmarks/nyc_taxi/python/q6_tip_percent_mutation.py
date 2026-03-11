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
        filter=pc.field("total_amount") > 0,
        columns=["tip_amount", "total_amount"],
    )
    frame = table.to_pandas()
    result = frame.assign(tip_percent=frame["tip_amount"] / frame["total_amount"] * 100.0)

    print(result.head(10))
    print("ROWS_SCANNED=NA")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

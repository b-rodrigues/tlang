import argparse
import time

import pandas as pd
import pyarrow.dataset as ds


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, help="Path to the partitioned parquet dataset")
    args = parser.parse_args()

    started = time.perf_counter()
    dataset = ds.dataset(args.dataset, format="parquet", partitioning="hive")

    # For q20 we load all columns used in a typical nest/unnest roundtrip
    # to be fair with T which might be materializing more than just 1-2 columns.
    # However, to be consistent with other baselines, we'll load the full set.
    table = dataset.to_table()
    frame = table.to_pandas()

    # Python equivalent of nest/unnest: groupby and concat
    # This captures the overhead of partitioning and reconstructing the dataframe.
    nested = [group for _, group in frame.groupby("VendorID", dropna=False)]
    result = pd.concat(nested)

    print(result.head(10))
    print("ROWS_SCANNED=NA")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

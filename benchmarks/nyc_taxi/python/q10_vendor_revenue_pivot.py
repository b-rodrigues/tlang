import argparse
import time

import pandas as pd
import pyarrow.dataset as ds


def vendor_label(value: object) -> str:
    if pd.isna(value):
        return "vendor_NA"
    if isinstance(value, float) and value.is_integer():
        return f"vendor_{int(value)}"
    return f"vendor_{value}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, help="Path to the partitioned parquet dataset")
    args = parser.parse_args()

    started = time.perf_counter()
    dataset = ds.dataset(args.dataset, format="parquet", partitioning="hive")

    table = dataset.to_table(columns=["year", "month", "VendorID", "total_amount"])
    frame = table.to_pandas()
    grouped = (
        frame.groupby(["year", "month", "VendorID"], dropna=False)
        .agg(rev=("total_amount", "sum"))
        .reset_index()
    )
    grouped["vendor_label"] = grouped["VendorID"].map(vendor_label)
    result = (
        grouped.pivot(index=["year", "month"], columns="vendor_label", values="rev")
        .reset_index()
        .sort_values(["year", "month"])
    )

    print(result.head(10))
    print("ROWS_SCANNED=NA")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

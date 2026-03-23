import argparse
import time

import pandas as pd


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-parquet", required=True, help="Path to a materialized parquet benchmark input")
    args = parser.parse_args()

    started = time.perf_counter()
    frame = pd.read_parquet(args.input_parquet)
    positive_total = frame["total_amount"] > 0
    result = frame.loc[positive_total].assign(
        tip_percent=frame.loc[positive_total, "tip_amount"] / frame.loc[positive_total, "total_amount"] * 100.0
    )

    print(result.head(10))
    print(f"ROWS_SCANNED={len(frame.index)}")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

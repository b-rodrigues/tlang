import argparse
import time

import pandas as pd


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-parquet", required=True, help="Path to a materialized parquet benchmark input")
    args = parser.parse_args()

    started = time.perf_counter()
    frame = pd.read_parquet(args.input_parquet)
    result = frame[
        (frame["passenger_count"] > 1)
        & (frame["trip_distance"] > 5)
        & (frame["payment_type"] == 1)
    ]

    print(result.head(10))
    print(f"ROWS_SCANNED={len(frame.index)}")
    print(f"ROWS_RETURNED={len(result.index)}")
    print(f"ELAPSED_SEC={time.perf_counter() - started:.6f}")


if __name__ == "__main__":
    main()

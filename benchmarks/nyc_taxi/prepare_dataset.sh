#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -z "${TLANG_NYC_TAXI_IN_NIX:-}" && -z "${IN_NIX_SHELL:-}" && -x "$(command -v nix || true)" ]]; then
  exec nix develop "$PROJECT_ROOT" -c env TLANG_NYC_TAXI_IN_NIX=1 bash "$0" "$@"
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --months YYYY-MM,YYYY-MM   Comma-separated list of monthly files to process
  --raw-dir PATH             Directory for downloaded CSV files
  --parquet-dir PATH         Output directory for the partitioned parquet dataset
  --materialized-csv PATH    Optional CSV output for T benchmarks
  --clean                    Remove existing parquet output before writing
  --keep-raw                 Keep downloaded CSV files after conversion
  --no-materialized-csv      Skip materialized CSV generation
  --help                     Show this message

Example:
  $(basename "$0") \\
    --months 2023-01,2023-02,2023-03 \\
    --raw-dir /tmp/nyc-taxi-raw \\
    --parquet-dir /tmp/nyc-taxi-parquet \\
    --materialized-csv /tmp/nyc-taxi-materialized.csv
EOF
}

MONTHS="2023-01,2023-02,2023-03"
RAW_DIR="$SCRIPT_DIR/data/raw"
PARQUET_DIR="$SCRIPT_DIR/data/nyc_taxi_parquet"
MATERIALIZED_CSV="$SCRIPT_DIR/data/nyc_taxi_materialized.csv"
TLC_TRIP_DATA_PAGE_URL="https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page"
KEEP_RAW=0
WRITE_MATERIALIZED=1
CLEAN_PARQUET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --months)
      MONTHS="${2:?missing value for --months}"
      shift 2
      ;;
    --raw-dir)
      RAW_DIR="${2:?missing value for --raw-dir}"
      shift 2
      ;;
    --parquet-dir)
      PARQUET_DIR="${2:?missing value for --parquet-dir}"
      shift 2
      ;;
    --materialized-csv)
      MATERIALIZED_CSV="${2:?missing value for --materialized-csv}"
      shift 2
      ;;
    --clean)
      CLEAN_PARQUET=1
      shift
      ;;
    --keep-raw)
      KEEP_RAW=1
      shift
      ;;
    --no-materialized-csv)
      WRITE_MATERIALIZED=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$RAW_DIR"
if [[ "$CLEAN_PARQUET" -eq 1 ]]; then
  rm -rf "$PARQUET_DIR"
fi
if [[ -d "$PARQUET_DIR" ]] && find "$PARQUET_DIR" -mindepth 1 -print -quit | grep -q .; then
  echo "Parquet output directory is not empty: $PARQUET_DIR" >&2
  echo "Re-running without cleaning can duplicate benchmark data. Use --clean to overwrite it." >&2
  exit 1
fi
mkdir -p "$PARQUET_DIR"
if [[ "$WRITE_MATERIALIZED" -eq 1 ]]; then
  mkdir -p "$(dirname "$MATERIALIZED_CSV")"
  rm -f "$MATERIALIZED_CSV"
fi

IFS=',' read -r -a MONTH_LIST <<< "$MONTHS"

resolve_tlc_dataset_url() {
  local month="$1"
  python - "$month" "$TLC_TRIP_DATA_PAGE_URL" <<'PY'
import re
import sys
import urllib.request

month = sys.argv[1]
page_url = sys.argv[2]

with urllib.request.urlopen(page_url) as response:
    html = response.read().decode("utf-8", errors="replace")

links = re.findall(r'https://[^"\']+/yellow_tripdata_\d{4}-\d{2}\.(?:parquet|csv)', html, flags=re.IGNORECASE)
normalized = sorted({link.lower() for link in links})
if not normalized:
    raise SystemExit(
        f"Could not find yellow taxi download links on official TLC page: {page_url}"
    )

target_suffixes = [f"yellow_tripdata_{month}.parquet", f"yellow_tripdata_{month}.csv"]
for suffix in target_suffixes:
    for link in normalized:
        if link.endswith(suffix):
            print(link)
            raise SystemExit(0)

sample = normalized[0]
match = re.search(r"/yellow_tripdata_\d{4}-\d{2}\.(parquet|csv)$", sample)
if match is None:
    raise SystemExit(f"Unexpected TLC dataset link format on {page_url}")

extension = match.group(1)
base = sample.rsplit("/", 1)[0]
print(f"{base}/yellow_tripdata_{month}.{extension}")
PY
}

for month in "${MONTH_LIST[@]}"; do
  [[ -n "$month" ]] || continue
  url="$(resolve_tlc_dataset_url "$month")"
  raw_input="$RAW_DIR/$(basename "$url")"

  echo "=== Processing ${month} ==="
  echo "Downloading ${url}"

  python - "$url" "$raw_input" <<'PY'
import pathlib
import sys
import urllib.request

url, output = sys.argv[1], pathlib.Path(sys.argv[2])
output.parent.mkdir(parents=True, exist_ok=True)
if not output.exists():
    urllib.request.urlretrieve(url, output)
else:
    print(f"Reusing existing download: {output}")
PY

  echo "Converting ${raw_input} -> ${PARQUET_DIR}"
  if [[ "$WRITE_MATERIALIZED" -eq 1 ]]; then
    python - "$raw_input" "$PARQUET_DIR" "$MATERIALIZED_CSV" <<'PY'
import pathlib
import re
import sys

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

raw_input = pathlib.Path(sys.argv[1])
parquet_dir = pathlib.Path(sys.argv[2])
materialized_csv = pathlib.Path(sys.argv[3])

match = re.search(r"(\d{4})-(\d{2})", raw_input.name)
if match is None:
    raise SystemExit(f"Could not infer year/month from file name: {raw_input.name}")

year = int(match.group(1))
month = int(match.group(2))

if raw_input.suffix.lower() == ".csv":
    df = pd.read_csv(raw_input)
elif raw_input.suffix.lower() == ".parquet":
    df = pd.read_parquet(raw_input)
else:
    raise SystemExit(f"Unsupported input format for benchmark data: {raw_input}")
if "year" not in df.columns:
    df["year"] = year
if "month" not in df.columns:
    df["month"] = month

table = pa.Table.from_pandas(df, preserve_index=False)
pq.write_to_dataset(table, root_path=str(parquet_dir), partition_cols=["year", "month"])

materialized_csv.parent.mkdir(parents=True, exist_ok=True)
write_header = not materialized_csv.exists()
df.to_csv(materialized_csv, mode="a", index=False, header=write_header)
print(f"Wrote parquet partitions and appended to {materialized_csv}")
PY
  else
    python - "$raw_input" "$PARQUET_DIR" <<'PY'
import pathlib
import re
import sys

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

raw_input = pathlib.Path(sys.argv[1])
parquet_dir = pathlib.Path(sys.argv[2])

match = re.search(r"(\d{4})-(\d{2})", raw_input.name)
if match is None:
    raise SystemExit(f"Could not infer year/month from file name: {raw_input.name}")

year = int(match.group(1))
month = int(match.group(2))

if raw_input.suffix.lower() == ".csv":
    df = pd.read_csv(raw_input)
elif raw_input.suffix.lower() == ".parquet":
    df = pd.read_parquet(raw_input)
else:
    raise SystemExit(f"Unsupported input format for benchmark data: {raw_input}")
if "year" not in df.columns:
    df["year"] = year
if "month" not in df.columns:
    df["month"] = month

table = pa.Table.from_pandas(df, preserve_index=False)
pq.write_to_dataset(table, root_path=str(parquet_dir), partition_cols=["year", "month"])
print(f"Wrote parquet partitions to {parquet_dir}")
PY
  fi

  if [[ "$KEEP_RAW" -eq 0 ]]; then
    rm -f "$raw_input"
  fi
done

echo "Done."
echo "Parquet dataset: $PARQUET_DIR"
if [[ "$WRITE_MATERIALIZED" -eq 1 ]]; then
  echo "Materialized CSV: $MATERIALIZED_CSV"
fi

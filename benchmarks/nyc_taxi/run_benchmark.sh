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
  --parquet-dir PATH   Path to the partitioned parquet dataset
  --csv-path PATH      Path to the materialized CSV used by T
  --months LIST        Comma-separated YYYY-MM list used if auto-preparing data
  --results PATH       Output CSV path
  --queries LIST       Comma-separated query ids (default: q1,q2,q3)
  --iterations N       Number of runs per engine/query (default: 1)
  --help               Show this message
EOF
}

PARQUET_DIR="$SCRIPT_DIR/data/nyc_taxi_parquet"
CSV_PATH="$SCRIPT_DIR/data/nyc_taxi_materialized.csv"
MONTHS="2023-01,2023-02,2023-03"
RESULTS_PATH="$SCRIPT_DIR/results/results.csv"
QUERIES="q1,q2,q3"
ITERATIONS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parquet-dir)
      PARQUET_DIR="${2:?missing value for --parquet-dir}"
      shift 2
      ;;
    --csv-path)
      CSV_PATH="${2:?missing value for --csv-path}"
      shift 2
      ;;
    --months)
      MONTHS="${2:?missing value for --months}"
      shift 2
      ;;
    --results)
      RESULTS_PATH="${2:?missing value for --results}"
      shift 2
      ;;
    --queries)
      QUERIES="${2:?missing value for --queries}"
      shift 2
      ;;
    --iterations)
      ITERATIONS="${2:?missing value for --iterations}"
      shift 2
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

if ! command -v python >/dev/null 2>&1; then
  echo "python is required" >&2
  exit 1
fi

directory_has_contents() {
  local path="$1"
  [[ -d "$path" ]] && find "$path" -mindepth 1 -print -quit | grep -q .
}

ensure_benchmark_inputs() {
  if ! directory_has_contents "$PARQUET_DIR"; then
    echo "Parquet dataset not found at $PARQUET_DIR. Preparing benchmark data for months: $MONTHS"
    bash "$SCRIPT_DIR/prepare_dataset.sh" \
      --months "$MONTHS" \
      --clean \
      --parquet-dir "$PARQUET_DIR" \
      --materialized-csv "$CSV_PATH"
    return
  fi

  if [[ -f "$CSV_PATH" ]]; then
    return
  fi

  echo "Materialized CSV not found at $CSV_PATH. Building it from the existing parquet dataset."
  python - "$PARQUET_DIR" "$CSV_PATH" <<'PY'
import pathlib
import sys

import pyarrow.dataset as ds

parquet_dir = pathlib.Path(sys.argv[1])
csv_path = pathlib.Path(sys.argv[2])

dataset = ds.dataset(str(parquet_dir), format="parquet", partitioning="hive")
csv_path.parent.mkdir(parents=True, exist_ok=True)

write_header = True
with csv_path.open("w", encoding="utf-8", newline="") as handle:
    for batch in dataset.to_batches():
        frame = batch.to_pandas()
        if frame.empty:
            continue
        frame.to_csv(handle, index=False, header=write_header)
        write_header = False

if write_header:
    csv_path.unlink(missing_ok=True)
    raise SystemExit(f"Parquet dataset at {parquet_dir} did not contain any rows.")

print(f"Materialized CSV written to {csv_path}")
PY
}

ensure_benchmark_inputs

if ! command -v Rscript >/dev/null 2>&1; then
  echo "Rscript is required" >&2
  exit 1
fi

# Find the actual binary path, ignoring shell functions/aliases
T_BIN="$(type -p t || true)"
if [[ -z "$T_BIN" || ! -x "$T_BIN" ]]; then
  if [[ -f "$PROJECT_ROOT/_build/default/src/repl.exe" ]]; then
    T_BIN="$PROJECT_ROOT/_build/default/src/repl.exe"
  elif [[ -L "$PROJECT_ROOT/result" && -f "$PROJECT_ROOT/result/bin/t" ]]; then
    T_BIN="$PROJECT_ROOT/result/bin/t"
  fi
fi

if [[ -z "$T_BIN" ]]; then
  echo "Error: 't' command not found in PATH and no compiled binary found in _build or result." >&2
  echo "Please run 'dune build' or 'nix build' to compile the T language before running benchmarks." >&2
  exit 1
fi



TIME_BIN=""
for candidate in time gtime; do
  if [[ "$candidate" = "/usr/bin/time" && ! -x "$candidate" ]]; then
    continue
  fi
  if [[ "$candidate" != "/usr/bin/time" ]] && ! command -v "$candidate" >/dev/null 2>&1; then
    continue
  fi
  if "$candidate" -f 'TIME_SEC=%e' bash -lc 'exit 0' >/dev/null 2>/dev/null; then
    TIME_BIN="$(command -v "$candidate" || echo "$candidate")"
    break
  fi
done

if [[ -z "$TIME_BIN" ]]; then
  echo "GNU time with -f support is required to record memory usage." >&2
  exit 1
fi

mkdir -p "$(dirname "$RESULTS_PATH")"
printf 'engine,query,iteration,time_sec,memory_mb,rows_scanned,rows_returned,status\n' > "$RESULTS_PATH"

metric_value() {
  local key="$1"
  local file="$2"
  awk -F= -v key="$key" '
    $1 == key {
      if ($2 != "") {
        value = $2
      } else if (getline next_line) {
        value = next_line
      }
    }
    END {
      if (value == "") print "NA"
      else print value
    }
  ' "$file"
}

run_query() {
  local engine="$1"
  local query="$2"
  local iteration="$3"
  shift 3

  local stdout_file
  local stderr_file
  local status
  local time_sec
  local memory_kb
  local memory_mb
  local rows_scanned
  local rows_returned
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  echo "=== ${engine} / ${query} / iteration ${iteration} ==="

  if "$TIME_BIN" -f 'TIME_SEC=%e\nMEMORY_KB=%M' "$@" >"$stdout_file" 2>"$stderr_file"; then
    status="ok"
  else
    status="fail"
  fi

  cat "$stdout_file"
  if [[ "$status" != "ok" ]]; then
    cat "$stderr_file" >&2
  fi

  time_sec="$(metric_value "TIME_SEC" "$stderr_file")"
  memory_kb="$(metric_value "MEMORY_KB" "$stderr_file")"
  if [[ "$memory_kb" == "NA" ]]; then
    memory_mb="NA"
  else
    memory_mb="$(python - "$memory_kb" <<'PY'
import sys
value = float(sys.argv[1])
print(f"{value / 1024.0:.2f}")
PY
)"
  fi

  rows_scanned="$(metric_value "ROWS_SCANNED" "$stdout_file")"
  rows_returned="$(metric_value "ROWS_RETURNED" "$stdout_file")"

  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$engine" "$query" "$iteration" "$time_sec" "$memory_mb" "$rows_scanned" "$rows_returned" "$status" \
    >> "$RESULTS_PATH"

  rm -f "$stdout_file" "$stderr_file"
}

IFS=',' read -r -a QUERY_LIST <<< "$QUERIES"

for query in "${QUERY_LIST[@]}"; do
  case "$query" in
    q1)
      python_script="$SCRIPT_DIR/python/q1_long_trips.py"
      r_script="$SCRIPT_DIR/r/q1_long_trips.R"
      t_script="$SCRIPT_DIR/queries/q1_long_trips.t"
      ;;
    q2)
      python_script="$SCRIPT_DIR/python/q2_group_passenger.py"
      r_script="$SCRIPT_DIR/r/q2_group_passenger.R"
      t_script="$SCRIPT_DIR/queries/q2_group_passenger.t"
      ;;
    q3)
      python_script="$SCRIPT_DIR/python/q3_monthly_stats.py"
      r_script="$SCRIPT_DIR/r/q3_monthly_stats.R"
      t_script="$SCRIPT_DIR/queries/q3_monthly_stats.t"
      ;;
    *)
      echo "Unknown query id: $query" >&2
      exit 1
      ;;
  esac

  for iteration in $(seq 1 "$ITERATIONS"); do
    run_query python "$query" "$iteration" python "$python_script" --dataset "$PARQUET_DIR"
    run_query r "$query" "$iteration" Rscript "$r_script" "$PARQUET_DIR"
    run_query t "$query" "$iteration" env NYC_TAXI_CSV="$CSV_PATH" "$T_BIN" run --unsafe "$t_script"
  done
done

echo "Benchmark results written to $RESULTS_PATH"

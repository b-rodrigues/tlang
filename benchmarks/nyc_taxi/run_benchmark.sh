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
  --results PATH       Output CSV path
  --queries LIST       Comma-separated query ids (default: q1,q2,q3)
  --iterations N       Number of runs per engine/query (default: 1)
  --help               Show this message
EOF
}

PARQUET_DIR="$SCRIPT_DIR/data/nyc_taxi_parquet"
CSV_PATH="$SCRIPT_DIR/data/nyc_taxi_materialized.csv"
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

if [[ ! -d "$PARQUET_DIR" ]]; then
  echo "Parquet dataset not found: $PARQUET_DIR" >&2
  exit 1
fi

if [[ ! -f "$CSV_PATH" ]]; then
  echo "Materialized CSV not found: $CSV_PATH" >&2
  exit 1
fi

if ! command -v python >/dev/null 2>&1; then
  echo "python is required" >&2
  exit 1
fi

if ! command -v Rscript >/dev/null 2>&1; then
  echo "Rscript is required" >&2
  exit 1
fi

if ! command -v t >/dev/null 2>&1; then
  echo "t is required" >&2
  exit 1
fi

TIME_BIN="$(command -v /usr/bin/time || true)"
if [[ -z "$TIME_BIN" ]]; then
  TIME_BIN="$(command -v time || true)"
fi
if [[ -z "$TIME_BIN" ]]; then
  echo "GNU time is required to record memory usage" >&2
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
    run_query t "$query" "$iteration" env NYC_TAXI_CSV="$CSV_PATH" t run "$t_script"
  done
done

echo "Benchmark results written to $RESULTS_PATH"

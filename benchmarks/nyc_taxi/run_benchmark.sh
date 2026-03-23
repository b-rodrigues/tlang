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
  --queries LIST       Comma-separated query ids (default: q1,q2,q3,q4,q5,q6,q7,q8,q9,q10,q11,q12,q13,q14,q15,q16,q17,q18,q19)
  --iterations N       Number of runs per engine/query (default: 1)
  --help               Show this message
EOF
}

PARQUET_DIR="$SCRIPT_DIR/data/nyc_taxi_parquet"
CSV_PATH="$SCRIPT_DIR/data/nyc_taxi_materialized.csv"
PARQUET_PATH="$SCRIPT_DIR/data/nyc_taxi_materialized.parquet"
MONTHS="2023-01,2023-02,2023-03"
RESULTS_PATH="$SCRIPT_DIR/results/results.csv"
QUERIES="q1,q2,q3,q4,q5,q6,q7,q8,q9,q10,q11,q12,q13,q14,q15,q16,q17,q18,q19"
ITERATIONS=1
CORE_100K_CSV="$SCRIPT_DIR/data/nyc_taxi_core_100k.csv"
CORE_100K_PARQUET="$SCRIPT_DIR/data/nyc_taxi_core_100k.parquet"
CORE_1M_CSV="$SCRIPT_DIR/data/nyc_taxi_core_1m.csv"
CORE_1M_PARQUET="$SCRIPT_DIR/data/nyc_taxi_core_1m.parquet"

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
    --parquet-path)
      PARQUET_PATH="${2:?missing value for --parquet-path}"
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
      --materialized-csv "$CSV_PATH" \
      --materialized-parquet "$PARQUET_PATH"
    return
  fi

  if [[ -f "$CSV_PATH" && -f "$PARQUET_PATH" ]]; then
    return
  fi

  echo "Materialized inputs missing. Building them from the existing parquet dataset."
  python - "$PARQUET_DIR" "$CSV_PATH" "$PARQUET_PATH" <<'PY'
import pathlib
import sys

import pyarrow.dataset as ds
import pyarrow.parquet as pq

parquet_dir = pathlib.Path(sys.argv[1])
csv_path = pathlib.Path(sys.argv[2])
parquet_path = pathlib.Path(sys.argv[3])

dataset = ds.dataset(str(parquet_dir), format="parquet", partitioning="hive")
csv_path.parent.mkdir(parents=True, exist_ok=True)

# Write CSV
write_header = True
with csv_path.open("w", encoding="utf-8", newline="") as handle:
    for batch in dataset.to_batches():
        frame = batch.to_pandas()
        if frame.empty:
            continue
        frame.to_csv(handle, index=False, header=write_header)
        write_header = False

# Write Parquet
table = dataset.to_table()
pq.write_table(table, parquet_path)

if write_header:
    csv_path.unlink(missing_ok=True)
    parquet_path.unlink(missing_ok=True)
    raise SystemExit(f"Parquet dataset at {parquet_dir} did not contain any rows.")

print(f"Materialized CSV written to {csv_path}")
print(f"Materialized Parquet written to {parquet_path}")
PY
}

ensure_benchmark_inputs

core_benchmark_query_requested() {
  case ",$QUERIES," in
    *,q14,*|*,q15,*|*,q16,*|*,q17,*|*,q18,*|*,q19,*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_core_subset() {
  local source_parquet="$1"
  local rows="$2"
  local output_csv="$3"
  local output_parquet="$4"

  if [[ -f "$output_csv" && -f "$output_parquet" ]]; then
    return
  fi

  mkdir -p "$(dirname "$output_csv")"
  mkdir -p "$(dirname "$output_parquet")"

  python - "$source_parquet" "$output_csv" "$output_parquet" "$rows" <<'PY'
import pathlib
import sys

import pyarrow.parquet as pq

source_parquet = pathlib.Path(sys.argv[1])
output_csv = pathlib.Path(sys.argv[2])
output_parquet = pathlib.Path(sys.argv[3])
rows = int(sys.argv[4])

table = pq.read_table(source_parquet)
if table.num_rows < rows:
    raise SystemExit(
        f"Materialized parquet at {source_parquet} only has {table.num_rows} rows; "
        f"need at least {rows} rows for the core verb benchmark."
    )

subset = table.slice(0, rows)
pq.write_table(subset, output_parquet)
subset.to_pandas().to_csv(output_csv, index=False)

print(f"Wrote {rows} rows to {output_parquet}")
print(f"Wrote {rows} rows to {output_csv}")
PY
}

if core_benchmark_query_requested; then
  ensure_core_subset "$PARQUET_PATH" 100000 "$CORE_100K_CSV" "$CORE_100K_PARQUET"
  ensure_core_subset "$PARQUET_PATH" 1000000 "$CORE_1M_CSV" "$CORE_1M_PARQUET"
fi

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
  python_args=(--dataset "$PARQUET_DIR")
  r_args=("$PARQUET_DIR")
  t_csv="$CSV_PATH"
  t_parquet="$PARQUET_PATH"

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
    q4)
      python_script="$SCRIPT_DIR/python/q4_high_cardinality_grouping.py"
      r_script="$SCRIPT_DIR/r/q4_high_cardinality_grouping.R"
      t_script="$SCRIPT_DIR/queries/q4_high_cardinality_grouping.t"
      ;;
    q5)
      python_script="$SCRIPT_DIR/python/q5_composite_grouping.py"
      r_script="$SCRIPT_DIR/r/q5_composite_grouping.R"
      t_script="$SCRIPT_DIR/queries/q5_composite_grouping.t"
      ;;
    q6)
      python_script="$SCRIPT_DIR/python/q6_tip_percent_mutation.py"
      r_script="$SCRIPT_DIR/r/q6_tip_percent_mutation.R"
      t_script="$SCRIPT_DIR/queries/q6_tip_percent_mutation.t"
      ;;
    q7)
      python_script="$SCRIPT_DIR/python/q7_monthly_unique_pickups.py"
      r_script="$SCRIPT_DIR/r/q7_monthly_unique_pickups.R"
      t_script="$SCRIPT_DIR/queries/q7_monthly_unique_pickups.t"
      ;;
    q8)
      python_script="$SCRIPT_DIR/python/q8_sort_total_amount_desc.py"
      r_script="$SCRIPT_DIR/r/q8_sort_total_amount_desc.R"
      t_script="$SCRIPT_DIR/queries/q8_sort_total_amount_desc.t"
      ;;
    q9)
      python_script="$SCRIPT_DIR/python/q9_complex_filters.py"
      r_script="$SCRIPT_DIR/r/q9_complex_filters.R"
      t_script="$SCRIPT_DIR/queries/q9_complex_filters.t"
      ;;
    q10)
      python_script="$SCRIPT_DIR/python/q10_vendor_revenue_pivot.py"
      r_script="$SCRIPT_DIR/r/q10_vendor_revenue_pivot.R"
      t_script="$SCRIPT_DIR/queries/q10_vendor_revenue_pivot.t"
      ;;
    q11)
      python_script="$SCRIPT_DIR/python/q11_heavy_summarize.py"
      r_script="$SCRIPT_DIR/r/q11_heavy_summarize.R"
      t_script="$SCRIPT_DIR/queries/q11_heavy_summarize.t"
      ;;
    q12)
      python_script="$SCRIPT_DIR/python/q12_multi_stage_rollup.py"
      r_script="$SCRIPT_DIR/r/q12_multi_stage_rollup.R"
      t_script="$SCRIPT_DIR/queries/q12_multi_stage_rollup.t"
      ;;
    q13)
      python_script="$SCRIPT_DIR/python/q13_high_cardinality_rollup.py"
      r_script="$SCRIPT_DIR/r/q13_high_cardinality_rollup.R"
      t_script="$SCRIPT_DIR/queries/q13_high_cardinality_rollup.t"
      ;;
    q14)
      python_script="$SCRIPT_DIR/python/q14_core_select.py"
      r_script="$SCRIPT_DIR/r/q14_core_select.R"
      t_script="$SCRIPT_DIR/queries/q14_core_select.t"
      python_args=(--input-parquet "$CORE_100K_PARQUET")
      r_args=("$CORE_100K_PARQUET")
      t_csv="$CORE_100K_CSV"
      t_parquet="$CORE_100K_PARQUET"
      ;;
    q15)
      python_script="$SCRIPT_DIR/python/q15_core_filter.py"
      r_script="$SCRIPT_DIR/r/q15_core_filter.R"
      t_script="$SCRIPT_DIR/queries/q15_core_filter.t"
      python_args=(--input-parquet "$CORE_100K_PARQUET")
      r_args=("$CORE_100K_PARQUET")
      t_csv="$CORE_100K_CSV"
      t_parquet="$CORE_100K_PARQUET"
      ;;
    q16)
      python_script="$SCRIPT_DIR/python/q16_core_mutate.py"
      r_script="$SCRIPT_DIR/r/q16_core_mutate.R"
      t_script="$SCRIPT_DIR/queries/q16_core_mutate.t"
      python_args=(--input-parquet "$CORE_100K_PARQUET")
      r_args=("$CORE_100K_PARQUET")
      t_csv="$CORE_100K_CSV"
      t_parquet="$CORE_100K_PARQUET"
      ;;
    q17)
      python_script="$SCRIPT_DIR/python/q17_core_select.py"
      r_script="$SCRIPT_DIR/r/q17_core_select.R"
      t_script="$SCRIPT_DIR/queries/q17_core_select.t"
      python_args=(--input-parquet "$CORE_1M_PARQUET")
      r_args=("$CORE_1M_PARQUET")
      t_csv="$CORE_1M_CSV"
      t_parquet="$CORE_1M_PARQUET"
      ;;
    q18)
      python_script="$SCRIPT_DIR/python/q18_core_filter.py"
      r_script="$SCRIPT_DIR/r/q18_core_filter.R"
      t_script="$SCRIPT_DIR/queries/q18_core_filter.t"
      python_args=(--input-parquet "$CORE_1M_PARQUET")
      r_args=("$CORE_1M_PARQUET")
      t_csv="$CORE_1M_CSV"
      t_parquet="$CORE_1M_PARQUET"
      ;;
    q19)
      python_script="$SCRIPT_DIR/python/q19_core_mutate.py"
      r_script="$SCRIPT_DIR/r/q19_core_mutate.R"
      t_script="$SCRIPT_DIR/queries/q19_core_mutate.t"
      python_args=(--input-parquet "$CORE_1M_PARQUET")
      r_args=("$CORE_1M_PARQUET")
      t_csv="$CORE_1M_CSV"
      t_parquet="$CORE_1M_PARQUET"
      ;;
    *)
      echo "Unknown query id: $query" >&2
      exit 1
      ;;
  esac

  for iteration in $(seq 1 "$ITERATIONS"); do
    run_query python "$query" "$iteration" python "$python_script" "${python_args[@]}"
    run_query r "$query" "$iteration" Rscript "$r_script" "${r_args[@]}"
    run_query t "$query" "$iteration" env NYC_TAXI_CSV="$t_csv" NYC_TAXI_PARQUET="$t_parquet" "$T_BIN" run --unsafe "$t_script"
  done
done

echo "Benchmark results written to $RESULTS_PATH"

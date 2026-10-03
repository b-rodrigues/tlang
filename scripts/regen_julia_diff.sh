#!/usr/bin/env bash
# Regenerate tests/julia_diff/case_*.txt (reads/binds truth) from
# case_*.jl using Julia's own parser via dump_symbols.jl.
# The test itself never invokes julia: the .txt files are checked in
# so the suite stays hermetic (no binary, no startup files, no depot,
# no network). Requires julia, e.g. inside `nix develop`.
# Truth format per case_*.txt: line 1 = sorted unique read symbols,
# line 2 = sorted unique top-level binds (may be empty), line 3 = MD5
# of the .jl bytes. The test refuses stale truth (edited .jl without
# regenerating) instead of comparing against it.
set -euo pipefail
cd "$(dirname "$0")/.."
md5_of() {
  if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | cut -d' ' -f1;
  else md5 -r "$1" | cut -d' ' -f1; fi
}
out=$(julia --startup-file=no tests/julia_diff/dump_symbols.jl tests/julia_diff)
declare -A reads binds
while IFS=$'\t' read -r stem syms; do
  if [[ "$stem" == *@binds ]]; then
    binds["${stem%@binds}"]="$syms"
  else
    reads["$stem"]="$syms"
  fi
done <<< "$out"
for stem in "${!reads[@]}"; do
  {
    echo "${reads[$stem]}"
    echo "${binds[$stem]:-}"
    md5_of "tests/julia_diff/${stem}.jl"
  } > "tests/julia_diff/${stem}.txt"
done
julia --version > tests/julia_diff/JULIA_VERSION
echo "regenerated $(ls tests/julia_diff/case_*.txt | wc -l) fixtures"

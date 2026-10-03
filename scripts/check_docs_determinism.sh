#!/usr/bin/env bash
# Determinism check for generated docs: regenerate twice and fail on
# any difference between the two runs. Covers help/docs.json and
# docs/reference (both produced by `t doc`). Generation is idempotent
# by design, so this only fails on nondeterminism (ordering, timestamps,
# random iteration). Staleness against git HEAD is a separate question:
# run `git status` after to spot it.
set -euo pipefail
cd "$(dirname "$0")/.."
T=${T:-dune exec src/repl.exe --}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
$T doc >/dev/null 2>&1
cp help/docs.json "$TMP/docs1.json"
cp -r docs/reference "$TMP/ref1"
$T doc >/dev/null 2>&1
if ! diff -q help/docs.json "$TMP/docs1.json" >/dev/null; then
  echo "FAIL: help/docs.json differs between two regenerations"
  exit 1
fi
if ! diff -rq docs/reference "$TMP/ref1"; then
  echo "FAIL: docs/reference differs between two regenerations"
  exit 1
fi
echo "docs deterministic across two regenerations"

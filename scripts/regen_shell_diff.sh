#!/usr/bin/env bash
# Regenerate tests/shell_diff/case_*.json from case_*.sh using shfmt.
# The test itself never invokes shfmt: the JSON is checked in so the
# suite stays hermetic (no network, no binaries beyond the dev shell).
# Requires shfmt, e.g.: nix run nixpkgs#shfmt
set -euo pipefail
cd "$(dirname "$0")/.."
SHFMT=${SHFMT:-nix run nixpkgs#shfmt --}
$SHFMT --version
for f in tests/shell_diff/case_*.sh; do
  $SHFMT --to-json < "$f" > "${f%.sh}.json"
done
$SHFMT --version > tests/shell_diff/SHFMT_VERSION
echo "regenerated $(ls tests/shell_diff/case_*.json | wc -l) fixtures"

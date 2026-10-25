#!/usr/bin/env bash
# Check the vendored PMML jars.
#
# flake.nix takes jpmml-statsmodels and jpmml-evaluator from vendor/pmml/,
# not from a network fetch. That removes the Maven build and the release
# download, but it also means the bytes in the repository are the whole
# supply chain for those tools. This script fails if a jar is missing,
# truncated, replaced, or if flake.nix fetches one again.
#
# The expected hashes are the published release assets (they match the
# fetchurl pins flake.nix used before the jars were vendored):
#   jpmml-statsmodels 1.3.13  pmml-statsmodels-example-executable-1.3.13.jar
#   jpmml-evaluator   1.7.7   pmml-evaluator-example-executable-1.7.7.jar
set -euo pipefail
cd "$(dirname "$0")/.."

status=0

check_jar() {
  local path=$1
  local expected=$2
  local tool=$3

  if [ ! -f "$path" ]; then
    echo "FAIL: $path is missing. It is committed to the repository and flake.nix requires it."
    status=1
    return
  fi

  local actual
  actual=$(sha256sum "$path" | cut -d' ' -f1)
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $path changed."
    echo "  expected $expected"
    echo "  actual   $actual"
    echo "  Restore the released $tool jar, or update this hash and the version"
    echo "  in flake.nix when you intend to upgrade the tool."
    status=1
  fi

  # A jar is a zip archive, so it starts with "PK". This catches a
  # truncated file or a checkout that converted it as text.
  if [ "$(head -c 2 "$path")" != "PK" ]; then
    echo "FAIL: $path is not a zip/jar archive (bad magic bytes)."
    status=1
  fi
}

check_jar vendor/pmml/jpmml-statsmodels.jar \
  bf0c2a1d9134d3d2763d1c6228c2cb71130e523055b6ec88e795f93df883cdb6 \
  jpmml-statsmodels
check_jar vendor/pmml/jpmml-evaluator.jar \
  3cf480824dc0d48163629244838d774af34a3f03e97b6c1367e234a010ec1f0e \
  jpmml-evaluator

# The jars are vendored so that no build reaches the network for them.
if grep -n 'jpmml.*releases/download' flake.nix; then
  echo "FAIL: flake.nix fetches a jpmml jar again. Use the vendored file under vendor/pmml/."
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "vendored PMML jars unchanged"
fi
exit "$status"

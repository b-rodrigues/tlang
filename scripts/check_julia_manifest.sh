#!/usr/bin/env bash
# Check that jl-package/Manifest.toml matches the Nix Julia depot.
#
# flake.nix builds julia-with-packages with a fixed package list. The dev
# shell puts jl-package first on JULIA_LOAD_PATH, so stale pins in
# jl-package/Manifest.toml shadow depot versions and break loads. After any
# change to that package list, copy the matching version plus git-tree-sha1
# stanzas from the fresh wrapper depot manifest into Manifest.toml.
# See jl-package/README.md.
#
# This script runs the Julia companion test suite with the repo env first.
# It fails when pins drift, so CI catches the drift.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v julia >/dev/null 2>&1; then
  echo "FAIL: julia not on PATH. Run inside 'nix develop'."
  exit 1
fi

julia --startup-file=no --project=jl-package jl-package/test/runtests.jl
echo "Julia Manifest matches depot"

#!/usr/bin/env bash
set -euo pipefail

SYSTEM="${1:-$(nix eval --raw --impure --expr 'builtins.currentSystem')}"

echo "=== Building all flake packages for $SYSTEM ==="
nix build \
  .#t-lang .#t-coverage .#tlang-python .#tlang-r .#tlang-julia-path \
  .#python-django .#python-django-314 \
  .#python-fsspec .#python-fsspec-314 \
  .#python-httpcore .#python-httpcore-314 \
  .#python-pyogrio .#python-pyogrio-314 \
  .#python-sh .#python-sh-314 \
  .#python-twisted .#python-twisted-314

echo ""
echo "=== Building devShell profile ==="
nix develop .#default --profile dev-shell-profile --command true

echo ""
echo "=== Pushing runtime closures to Cachix (rstats-on-nix) ==="
nix path-info --recursive \
  .#t-lang .#t-coverage .#tlang-python .#tlang-r .#tlang-julia-path \
  .#python-django .#python-django-314 \
  .#python-fsspec .#python-fsspec-314 \
  .#python-httpcore .#python-httpcore-314 \
  .#python-pyogrio .#python-pyogrio-314 \
  .#python-sh .#python-sh-314 \
  .#python-twisted .#python-twisted-314 \
  | cachix push rstats-on-nix

echo ""
echo "=== Pushing build-time input closure ==="
SHELL_DRV=$(nix path-info --derivation ".#devShells.$SYSTEM.default")
nix-store --query --requisites "$SHELL_DRV" \
  | grep -v '\.drv$' \
  | cachix push rstats-on-nix

echo ""
echo "=== Pushing devShell profile closure ==="
nix path-info --recursive ./dev-shell-profile \
  | cachix push rstats-on-nix

echo ""
echo "Done!"

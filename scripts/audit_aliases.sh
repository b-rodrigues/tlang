#!/usr/bin/env bash

# List of known aliases that should not exist
ALIASES=(
  "ceil"
  "mday"
  "to_numeric"
  "as_factor"
  "py"
  "jl_node"
  "casewhen"
  "add_diagnostics"
)

echo "Auditing for deprecated aliases..."
echo "=================================="

FOUND=0

# 1. Search for known hardcoded aliases
for alias in "${ALIASES[@]}"; do
  grep -rE "\b${alias}\b" src/ tests/ --exclude-dir=_build --exclude="*.md" | grep -vE "(\(\*|--#|//)" > /tmp/alias_matches
  
  if [ -s /tmp/alias_matches ]; then
    echo "Found usage of deprecated alias '${alias}':"
    cat /tmp/alias_matches
    FOUND=1
  fi
done

# 2. Search for common OCaml alias patterns
# Pattern: let some_name = some_other_name (where both are in the same scope)
# This is noisy, so we look specifically for registrations
echo "Searching for multiple registrations of the same function..."
grep -r "Env.add" src/ --exclude-dir=_build | sort | uniq -d -f 2 > /tmp/duplicate_registrations
if [ -s /tmp/duplicate_registrations ]; then
    echo "Potential duplicate registrations found (check if they are aliases):"
    cat /tmp/duplicate_registrations
    FOUND=1
fi

# 3. Search for "let alias = original" in package files
echo "Searching for 'let alias = original' patterns..."
grep -rE "^let [a-zA-Z0-9_]+ = [a-zA-Z0-9_]+$" src/packages/ --exclude-dir=_build | grep -vE "(_env|env|args)" > /tmp/let_aliases
if [ -s /tmp/let_aliases ]; then
    echo "Potential 'let' aliases found:"
    cat /tmp/let_aliases
    FOUND=1
fi

if [ $FOUND -eq 0 ]; then
  echo "No deprecated aliases found in source code."
  exit 0
else
  echo "----------------------------------"
  echo "FAIL: Deprecated aliases detected."
  exit 1
fi

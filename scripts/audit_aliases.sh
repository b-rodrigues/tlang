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
)

echo "Auditing for deprecated aliases..."
echo "=================================="

FOUND=0

# 1. Search for known hardcoded aliases.
# Match registrations (Env.add "name") and calls (name().
# Require "(" after the name. This excludes Float.ceil,
# py-env, .py files, python, and plain words in comments.
for alias in "${ALIASES[@]}"; do
  rm -f /tmp/alias_matches
  touch /tmp/alias_matches
  grep -rnE "Env\.add[[:space:]]+\"${alias}\"" src/ tests/ --exclude-dir=_build --exclude="*.md" 2>/dev/null | grep -vE "(\(\*|--#|//)" >> /tmp/alias_matches || true
  grep -rnE "\b${alias}[[:space:]]*\(" src/ tests/ --exclude-dir=_build --exclude="*.md" 2>/dev/null | grep -vE "\.${alias}[[:space:]]*\(" | grep -vE "(\(\*|--#|//)" >> /tmp/alias_matches || true

  if [ -s /tmp/alias_matches ]; then
    echo "Found usage of deprecated alias '${alias}':"
    cat /tmp/alias_matches
    FOUND=1
  fi
done

# 2. Search for duplicate Env.add "name" registrations.
# Extract only the registered name, then report names seen twice.
# Known intentional overloads (same name, different package) are excluded:
# slice, contains, starts_with, ends_with live in colcraft and strcraft;
# to_string lives in converters and strcraft. See summary.md.
echo "Searching for multiple registrations of the same function..."
grep -rhoE 'Env\.add[[:space:]]+"[^"]+"' src/ --exclude-dir=_build 2>/dev/null | sort | uniq -d | grep -vE '"(slice|contains|starts_with|ends_with|to_string)"' > /tmp/duplicate_registrations || true
if [ -s /tmp/duplicate_registrations ]; then
    echo "Potential duplicate registrations found (check if they are aliases):"
    cat /tmp/duplicate_registrations
    FOUND=1
fi

# 3. Search for "let alias = original" in package files.
# Only top-level "let" (column 0) counts. Indented "let" inside
# functions binds local values, not package aliases.
# The name must start with a lowercase letter. This excludes numbers.
# Exclude OCaml keywords (function, fun, match, true, false, None, ...).
# Plain "let x = function" is a definition, not an alias.
echo "Searching for 'let alias = original' patterns..."
grep -rnE "^let [a-z][a-zA-Z0-9_']* = [a-z][a-zA-Z0-9_']*$" src/packages/ --exclude-dir=_build 2>/dev/null | grep -vE "= (function|fun|match|if|try|true|false|None|Some|Ok|Error|ref)([^a-zA-Z0-9_']|$)" | grep -vE "(_env|env|args)" > /tmp/let_aliases || true
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

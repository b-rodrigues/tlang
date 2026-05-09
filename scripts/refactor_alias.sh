#!/usr/bin/env bash

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <old_name> <new_name>"
    exit 1
fi

OLD=$1
NEW=$2

echo "Replacing '${OLD}' with '${NEW}' across the codebase..."

# Replace in OCaml files
find src tests -type f \( -name "*.ml" -o -name "*.mli" -o -name "*.t" \) -exec sed -i "s/\b${OLD}\b/${NEW}/g" {} +

# Replace in Markdown documentation
find docs -type f -name "*.md" -exec sed -i "s/\b${OLD}\b/${NEW}/g" {} +

# Replace in READMEs
find . -type f -name "README.md" -exec sed -i "s/\b${OLD}\b/${NEW}/g" {} +

echo "Done. Please review changes and run tests."

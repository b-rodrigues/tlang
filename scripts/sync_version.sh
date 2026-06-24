#!/usr/bin/env bash
# scripts/sync_version.sh
# Syncs the version from VERSION file to documentation and other files.

set -e

VERSION=$(cat VERSION | tr -d '\n')
TAG="v$VERSION"

# Extract codename from src/repl.ml
CODENAME=$(grep -o 'version "[^"]*" nix_version' src/repl.ml | head -n1 | cut -d'"' -f2)
CODENAME_URL=$(echo -n "$CODENAME" | sed "s/'/%27/g; s/ /%20/g")

echo "Syncing version $VERSION (\"$CODENAME\") to documentation..."

# README.md badges and text
sed -i "s/Beta%20[0-9.]*%20%22[^-]*/Beta%20$VERSION%20%22$CODENAME_URL%22/g" README.md
sed -i "s/Beta [0-9.]* \"[^\"]*\"/Beta $VERSION \"$CODENAME\"/g" README.md

# docs/index.md
sed -i "s/Version [0-9.]* \"[^\"]*\"/Version $VERSION \"$CODENAME\"/g" docs/index.md

# docs/language_overview.md
sed -i "s/Version\*\*: [0-9.]*/Version\*\*: $VERSION/g" docs/language_overview.md

# docs/project_development.md
sed -i "s/min_version = \"[0-9.]*\"/min_version = \"$VERSION\"/g" docs/project_development.md

# docs/reproducibility.md
sed -i "s/tlang\/v[0-9.]*/tlang\/$TAG/g" docs/reproducibility.md
sed -i "s/t_version: \"[0-9.]*\"/t_version: \"$VERSION\"/g" docs/reproducibility.md

# docs/installation.md
sed -i "s/Version [0-9.]* \"[^\"]*\"/Version $VERSION \"$CODENAME\"/g" docs/installation.md

echo "Done. Please review changes and commit."

#!/usr/bin/env bash
# scripts/sync_version.sh
# Syncs the version from VERSION file to documentation and other files.

set -e

VERSION=$(cat VERSION | tr -d '\n')
TAG="v$VERSION"

echo "Syncing version $VERSION to documentation..."

# README.md badges and text
sed -i "s/Beta%20[0-9.]*/Beta%20$VERSION/g" README.md
sed -i "s/Alpha [0-9.]*/Alpha $VERSION/g" README.md

# docs/index.md
sed -i "s/Version [0-9.]*/Version $VERSION/g" docs/index.md

# docs/language_overview.md
sed -i "s/Version\*\*: [0-9.]*/Version\*\*: $VERSION/g" docs/language_overview.md

# docs/project_development.md
sed -i "s/min_version = \"[0-9.]*\"/min_version = \"$VERSION\"/g" docs/project_development.md

# docs/reproducibility.md
sed -i "s/tlang\/v[0-9.]*/tlang\/$TAG/g" docs/reproducibility.md
sed -i "s/t_version: \"[0-9.]*\"/t_version: \"$VERSION\"/g" docs/reproducibility.md

# docs/installation.md
sed -i "s/(Alpha [0-9.]*)/(Alpha $VERSION)/g" docs/installation.md

echo "Done. Please review changes and commit."

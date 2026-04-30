#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

echo "Building HTML from Markdown via pandoc..."

# Determine if we're on macOS (Darwin) for sed -i compatibility
SED_INPLACE_EXT=""
if [[ "$OSTYPE" == "darwin"* ]]; then
  SED_INPLACE_EXT="''"
fi

for file in *.md; do
  if [ "$file" != "README.md" ]; then
    filename="${file%.*}"
    echo "Compiling $file -> $filename.html"
    pandoc "$file" -o "$filename.html" \
      --standalone \
      --css=style.css \
      --include-before-body=header.html \
      --include-after-body=footer.html \
      --metadata pagetitle="T Programming Language - $filename"
    
    # Post-process: convert .md links to .html
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's/\.md"/.html"/g' "$filename.html"
      sed -i '' 's/\.md)/.html)/g' "$filename.html"
    else
      sed -i 's/\.md"/.html"/g' "$filename.html"
      sed -i 's/\.md)/.html)/g' "$filename.html"
    fi
  fi
done

if [ -d "reference" ]; then
  for file in reference/*.md; do
    if [ -f "$file" ]; then
      filename="${file%.*}"
      echo "Compiling $file -> $filename.html"
      pandoc "$file" -o "$filename.html" \
        --standalone \
        --css=../style.css \
        --include-before-body=header_ref.html \
        --include-after-body=footer.html \
        --metadata pagetitle="T Function Reference - $(basename "$filename")"
      
      # Post-process: convert .md links to .html
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' 's/\.md"/.html"/g' "$filename.html"
        sed -i '' 's/\.md)/.html)/g' "$filename.html"
      else
        sed -i 's/\.md"/.html"/g' "$filename.html"
        sed -i 's/\.md)/.html)/g' "$filename.html"
      fi
    fi
  done
fi

echo "Generating huge reference for AI agents..."
HUGE_REF="../agents/t-reference-huge.md"
echo "# T Language Reference (Huge - Full Documentation)" > "$HUGE_REF"
echo -e "\nThis file is a concatenation of the entire T documentation for LLM context.\n" >> "$HUGE_REF"

# Core foundational files first
FOUNDATIONAL="index.md getting-started.md language_overview.md api-reference.md"
for f in $FOUNDATIONAL; do
  if [ -f "$f" ]; then
    echo -e "\n\n# FILE: docs/$f\n" >> "$HUGE_REF"
    cat "$f" >> "$HUGE_REF"
  fi
done

# All other files recursively (excluding foundational and README)
find . -name "*.md" | sort | while read -r f; do
  rel_path=${f#./}
  if [[ "$FOUNDATIONAL" == *"$rel_path"* ]] || [ "$rel_path" == "README.md" ]; then
    continue
  fi
  echo -e "\n\n# FILE: docs/$rel_path\n" >> "$HUGE_REF"
  cat "$f" >> "$HUGE_REF"
done

echo "Done!"

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
      --metadata title="T Programming Language - $filename"
    
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
        --metadata title="T Function Reference - $(basename "$filename")"
      
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

echo "Done!"

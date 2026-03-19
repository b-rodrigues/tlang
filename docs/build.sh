#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

echo "Building HTML from Markdown via pandoc..."

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
    sed -i 's/\.md"/.html"/g' "$filename.html"
    sed -i 's/\.md)/.html)/g' "$filename.html"
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
      sed -i 's/\.md"/.html"/g' "$filename.html"
      sed -i 's/\.md)/.html)/g' "$filename.html"
    fi
  done
fi

echo "Done!"

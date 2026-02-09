#!/usr/bin/env bash

# Run all T test scripts and generate output CSVs

set -e

T_REPL="dune exec src/repl.exe --"
SCRIPT_DIR="tests/golden/t_scripts"
OUTPUT_DIR="tests/golden/t_outputs"

mkdir -p "$OUTPUT_DIR"

echo "=== Running All T Golden Tests ==="
echo ""

passed=0
failed=0
skipped=0

for script in "$SCRIPT_DIR"/*.t; do
  test_name=$(basename "$script" .t)
  echo -n "Running: $test_name ... "
  
  # Run the script and capture output
  output=$($T_REPL run "$script" 2>&1 || true)
  
  # Check if test was skipped (contains "not yet implemented")
  if echo "$output" | grep -q "not yet implemented"; then
    echo "⚠ SKIPPED (not implemented)"
    ((skipped++))
  # Check if test succeeded (contains checkmark)
  elif echo "$output" | grep -q "✓"; then
    echo "✓ PASSED"
    ((passed++))
  else
    echo "❌ FAILED"
    echo "   Output: $output"
    ((failed++))
  fi
done

echo ""
echo "=== Results ==="
echo "  Passed:  $passed"
echo "  Failed:  $failed"
echo "  Skipped: $skipped"

if [ $failed -eq 0 ]; then
  echo "✅ All implemented tests passed!"
  exit 0
else
  echo "❌ Some tests failed"
  exit 1
fi

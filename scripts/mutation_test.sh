#!/usr/bin/env bash
# Mutation test: verify that the test suite catches regressions
# Temporarily breaks a known function and checks that tests fail

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVAL_FILE="$REPO_ROOT/src/eval.ml"
BACKUP_FILE="$REPO_ROOT/src/eval.ml.bak"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd "$REPO_ROOT"

# Ensure we always restore the original, even on Ctrl+C or script errors
cleanup() {
  if [ -f "$BACKUP_FILE" ]; then
    echo ""
    echo -e "${YELLOW}Restoring original eval.ml (caught signal/error)...${NC}"
    mv "$BACKUP_FILE" "$EVAL_FILE"
    echo -e "${GREEN}  ✓ Restored${NC}"
  fi
}
trap cleanup EXIT INT TERM

run_tests() {
  nix develop --command dune exec tests/test_runner.exe 2>&1 | grep -E "^=== Results:" | head -1
}

echo "=== Mutation Test ==="
echo ""

# Step 1: Verify tests pass before mutation
echo -e "${YELLOW}Step 1: Verifying tests pass before mutation...${NC}"
RESULT=$(run_tests)
if echo "$RESULT" | grep -q "3110/3110"; then
  echo -e "${GREEN}  ✓ All tests pass before mutation${NC}"
else
  echo -e "${RED}  ✗ Tests already fail before mutation: $RESULT. Aborting.${NC}"
  exit 1
fi

echo ""

# Step 2: Apply mutation
echo -e "${YELLOW}Step 2: Applying mutation (integer addition: a + b -> a * b)...${NC}"
cp "$EVAL_FILE" "$BACKUP_FILE"
sed -i 's/| (Plus, VInt a, VInt b) -> VInt (a + b)/| (Plus, VInt a, VInt b) -> VInt (a * b)/' "$EVAL_FILE"

if grep -q 'VInt (a \* b)' "$EVAL_FILE"; then
  echo -e "${GREEN}  ✓ Mutation applied${NC}"
else
  echo -e "${RED}  ✗ Mutation not applied (pattern not found)${NC}"
  exit 1
fi

echo ""

# Step 3: Build with mutation and run tests
echo -e "${YELLOW}Step 3: Building and running tests with mutated code...${NC}"
nix develop --command dune build 2>/dev/null
RESULT=$(run_tests)
if echo "$RESULT" | grep -q "3110/3110"; then
  echo -e "${RED}  ✗ MUTATION SURVIVED: Tests still pass with broken integer addition!${NC}"
  echo "  Result: $RESULT"
  exit 1
else
  echo -e "${GREEN}  ✓ MUTATION KILLED: Tests correctly fail${NC}"
  echo "  Result: $RESULT"
fi

echo ""

# Step 4: Restore original
echo -e "${YELLOW}Step 4: Restoring original code...${NC}"
mv "$BACKUP_FILE" "$EVAL_FILE"
echo -e "${GREEN}  ✓ Original code restored${NC}"

echo ""

# Step 5: Verify tests pass after restoration
echo -e "${YELLOW}Step 5: Verifying tests pass after restoration...${NC}"
nix develop --command dune build 2>/dev/null
RESULT=$(run_tests)
if echo "$RESULT" | grep -q "3110/3110"; then
  echo -e "${GREEN}  ✓ All tests pass after restoration${NC}"
else
  echo -e "${RED}  ✗ Tests fail after restoration: $RESULT${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}=== Mutation test complete: test suite is healthy ===${NC}"

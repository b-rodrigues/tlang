#!/usr/bin/env bash
# Mutation test: verify that the test suite catches regressions
# Temporarily breaks a known function and checks that tests fail
#
# Usage:
#   ./scripts/mutation_test.sh            # run all mutations
#   ./scripts/mutation_test.sh <name>     # run a single mutation (e.g. "if_else_swap")

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVAL_FILE="$REPO_ROOT/src/eval.ml"
BACKUP_FILE="$REPO_ROOT/src/eval.ml.bak"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd "$REPO_ROOT"

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

all_passed() {
  local line="$1"
  if [ -z "$line" ]; then return 1; fi
  local nums=($(echo "$line" | grep -oE '[0-9]+'))
  if [ ${#nums[@]} -ge 2 ] && [ "${nums[0]}" -gt 0 ] && [ "${nums[0]}" -eq "${nums[1]}" ]; then
    return 0
  else
    return 1
  fi
}

apply_mutation() {
  local name="$1"

  echo -e "${YELLOW}  Applying: $name${NC}"
  cp "$EVAL_FILE" "$BACKUP_FILE"

  case "$name" in
    integer_add)
      perl -i -pe 's/\| \(Plus, VInt a, VInt b\) -> VInt \(a \+ b\)/| (Plus, VInt a, VInt b) -> VInt (a * b)/' "$EVAL_FILE"
      ;;
    if_else_swap)
      perl -i -0pe 's/\| VBool true -> eval_expr env_ref then_\n(\s*)\| VBool false -> eval_expr env_ref else_/| VBool true -> eval_expr env_ref else_\n$1| VBool false -> eval_expr env_ref then_/' "$EVAL_FILE"
      ;;
    unary_not)
      perl -i -pe 's/\(Not, VBool b\) -> VBool \(not b\)/(Not, VBool b) -> VBool b/' "$EVAL_FILE"
      ;;
    na_silent_pass)
      perl -i -0pe 's/Error\.na_predicate_error "Operation on NA: NA values do not propagate implicitly\. Handle missingness explicitly\."/VNA NAGeneric/' "$EVAL_FILE"
      ;;
  esac

  nix develop --command dune build 2>/dev/null
  local result
  result=$(run_tests)
  if all_passed "$result"; then
    echo -e "${RED}  ✗ MUTATION SURVIVED ($name): Tests still pass!${NC}"
    echo "    Result: $result"
    mv "$BACKUP_FILE" "$EVAL_FILE"
    return 1
  else
    echo -e "${GREEN}  ✓ MUTATION KILLED ($name): Tests correctly fail${NC}"
    echo "    Result: $result"
    mv "$BACKUP_FILE" "$EVAL_FILE"
    return 0
  fi
}

echo "=== Mutation Test ==="
echo ""

# Step 1: Verify tests pass before mutation
echo -e "${YELLOW}Step 1: Verifying tests pass before mutation...${NC}"
RESULT=$(run_tests)
if all_passed "$RESULT"; then
  echo -e "${GREEN}  ✓ All tests pass before mutation ($RESULT)${NC}"
else
  echo -e "${RED}  ✗ Tests already fail before mutation: $RESULT. Aborting.${NC}"
  exit 1
fi

echo ""

# Step 2-4: Run each mutation
declare -a MUTATION_NAMES=(
  "integer_add"
  "if_else_swap"
  "unary_not"
  "na_silent_pass"
)

KILLED=0
SURVIVED=0
FAILED_MUTATIONS=()

SINGLE_MUTATION="${1:-}"
for name in "${MUTATION_NAMES[@]}"; do
  if [ -n "$SINGLE_MUTATION" ] && [ "$name" != "$SINGLE_MUTATION" ]; then
    continue
  fi
  echo -e "${YELLOW}Testing mutation: $name${NC}"
  if apply_mutation "$name"; then
    ((KILLED++))
  else
    ((SURVIVED++))
    FAILED_MUTATIONS+=("$name")
  fi
  echo ""
done

# Step 5: Verify tests pass after all mutations restored
echo -e "${YELLOW}Verifying tests pass after all mutations restored...${NC}"
nix develop --command dune build 2>/dev/null
RESULT=$(run_tests)
if all_passed "$RESULT"; then
  echo -e "${GREEN}  ✓ All tests pass after restoration${NC}"
else
  echo -e "${RED}  ✗ Tests fail after restoration: $RESULT${NC}"
  exit 1
fi

echo ""
TOTAL=$((KILLED + SURVIVED))
if [ "$SURVIVED" -gt 0 ]; then
  echo -e "${RED}=== Mutation test: $KILLED/$TOTAL killed, $SURVIVED survived: ${FAILED_MUTATIONS[*]} ===${NC}"
  exit 1
else
  echo -e "${GREEN}=== Mutation test: $KILLED/$TOTAL killed — test suite is healthy ===${NC}"
fi

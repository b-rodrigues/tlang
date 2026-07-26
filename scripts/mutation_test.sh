#!/usr/bin/env bash
# Mutation test: verify that the test suite catches regressions
# Temporarily breaks a known function and checks that tests fail
#
# Usage:
#   ./scripts/mutation_test.sh            # run all mutations
#   ./scripts/mutation_test.sh <name>     # run a single mutation (e.g. "if_else_swap")

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd "$REPO_ROOT"

# Associative array tracking all backed-up files for current mutation
declare -A BACKUPS=()

backup_file() {
  local filepath="$1"
  local bak="${filepath}.bak"
  cp "$filepath" "$bak"
  BACKUPS["$filepath"]="$bak"
}

restore_all() {
  for filepath in "${!BACKUPS[@]}"; do
    local bak="${BACKUPS[$filepath]}"
    if [ -f "$bak" ]; then
      mv "$bak" "$filepath"
    fi
  done
  BACKUPS=()
}

cleanup() {
  if [ ${#BACKUPS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Restoring mutated files (caught signal/error)...${NC}"
    restore_all
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

  case "$name" in
    # ── eval.ml mutations ──────────────────────────────────────────────
    integer_add)
      backup_file "$REPO_ROOT/src/eval.ml"
      perl -i -pe 's/\| \(Plus, VInt a, VInt b\) -> VInt \(a \+ b\)/| (Plus, VInt a, VInt b) -> VInt (a * b)/' "$REPO_ROOT/src/eval.ml"
      ;;
    if_else_swap)
      backup_file "$REPO_ROOT/src/eval.ml"
      perl -i -0pe 's/\| VBool true -> eval_expr env_ref then_\n(\s*)\| VBool false -> eval_expr env_ref else_/| VBool true -> eval_expr env_ref else_\n$1| VBool false -> eval_expr env_ref then_/' "$REPO_ROOT/src/eval.ml"
      ;;
    unary_not)
      backup_file "$REPO_ROOT/src/eval.ml"
      perl -i -pe 's/\(Not, VBool b\) -> VBool \(not b\)/(Not, VBool b) -> VBool b/' "$REPO_ROOT/src/eval.ml"
      ;;
    na_silent_pass)
      backup_file "$REPO_ROOT/src/eval.ml"
      perl -i -0pe 's/Error\.na_predicate_error "Operation on NA: NA values do not propagate implicitly\. Handle missingness explicitly\."/VNA NAGeneric/' "$REPO_ROOT/src/eval.ml"
      ;;

    # ── arrow_compute.ml mutations ─────────────────────────────────────
    arrow_add_scalar)
      backup_file "$REPO_ROOT/src/arrow/arrow_compute.ml"
      perl -i -0pe 's/(let add_scalar.*?column_scalar_op table name scalar_value) \( \+\. \)/$1 (-.)/s' "$REPO_ROOT/src/arrow/arrow_compute.ml"
      ;;
    arrow_compare_gt)
      backup_file "$REPO_ROOT/src/arrow/arrow_compute.ml"
      perl -i -pe 's/\| Gt -> \( > \)/| Gt -> ( < )/' "$REPO_ROOT/src/arrow/arrow_compute.ml"
      ;;

    # ── clean_colnames.ml mutations ────────────────────────────────────
    clean_safe_char)
      backup_file "$REPO_ROOT/src/packages/dataframe/clean_colnames.ml"
      perl -i -pe 's/c >= .a. && c <= .z./c > '\''a'\'' \&\& c <= '\''z'\''/' "$REPO_ROOT/src/packages/dataframe/clean_colnames.ml"
      ;;
    clean_collision)
      backup_file "$REPO_ROOT/src/packages/dataframe/clean_colnames.ml"
      perl -i -pe 's/Hashtbl\.replace seen name \(count \+ 1\)/Hashtbl.replace seen name (count - 1)/' "$REPO_ROOT/src/packages/dataframe/clean_colnames.ml"
      ;;

    # ── t_read_csv.ml mutations ────────────────────────────────────────
    csv_type_fallback)
      backup_file "$REPO_ROOT/src/packages/dataframe/t_read_csv.ml"
      perl -i -pe 's/\| _ -> VString trimmed/| _ -> VInt 0/' "$REPO_ROOT/src/packages/dataframe/t_read_csv.ml"
      ;;
  esac

  # Verify at least one file was changed
  local changed=false
  for filepath in "${!BACKUPS[@]}"; do
    if ! diff -q "${BACKUPS[$filepath]}" "$filepath" > /dev/null 2>&1; then
      changed=true
      break
    fi
  done

  if [ "$changed" = false ]; then
    echo -e "${RED}  ✗ Mutation pattern did not match — no change applied ($name)${NC}"
    restore_all
    return 1
  fi

  nix develop --command dune build 2>/dev/null
  local result
  result=$(run_tests)
  if all_passed "$result"; then
    echo -e "${RED}  ✗ MUTATION SURVIVED ($name): Tests still pass!${NC}"
    echo "    Result: $result"
    restore_all
    return 1
  else
    echo -e "${GREEN}  ✓ MUTATION KILLED ($name): Tests correctly fail${NC}"
    echo "    Result: $result"
    restore_all
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
  "arrow_add_scalar"
  "arrow_compare_gt"
  "clean_safe_char"
  "clean_collision"
  "csv_type_fallback"
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
    KILLED=$((KILLED + 1))
  else
    SURVIVED=$((SURVIVED + 1))
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
if [ "$TOTAL" -eq 0 ]; then
  echo -e "${RED}=== No mutations matched${NC}"
  if [ -n "$SINGLE_MUTATION" ]; then
    echo -e "${RED}  Unknown mutation name: $SINGLE_MUTATION${NC}"
    echo -e "${RED}  Available: ${MUTATION_NAMES[*]}${NC}"
  fi
  exit 1
fi
if [ "$SURVIVED" -gt 0 ]; then
  echo -e "${RED}=== Mutation test: $KILLED/$TOTAL killed, $SURVIVED survived: ${FAILED_MUTATIONS[*]} ===${NC}"
  exit 1
else
  echo -e "${GREEN}=== Mutation test: $KILLED/$TOTAL killed — test suite is healthy ===${NC}"
fi

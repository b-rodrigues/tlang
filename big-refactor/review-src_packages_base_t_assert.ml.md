# Review: `src/packages/base/t_assert.ml`

## Summary

**Score: 9/10** — Well-structured and safe. The `register` function is long due to the builtin registration pattern, but each inner function is clear and correct.

---

## Checklist Results

### 1. CRITICAL — Partial Pattern Match (`Ast.value` constructors)
**Verdict: PASS** — No partial matches.

Every match expression is exhaustive:
- `assertion_failure` (L3): `Some msg` / `None` — exhaustive on `option`
- `path_arg` (L8), `message_arg` (L17): `VString` + `other` catch-all
- `expected_size_arg` (L26): `VInt n when n >= 0` / `VInt _` / `other`
- `inspect_file_target` (L44): `Unix.S_REG` / `_` (catch-all on Unix.st_kind) / `exception Unix.Unix_error _`
- `inspect_directory_target` (L55): `Unix.S_DIR` / `_` / `exception Unix.Unix_error _`
- `register` / `assert` handler (L87): `[v]` / `[v; VString _]` / `[_; other]` / `_`
- All `assert_file_exists` / `assert_dir_exists` / `assert_size_of_file` / `assert_non_empty_file` handlers: `[path]` / `[path; msg]` / `_`
- All `Result` matches (`Ok` / `Error`): exhaustive

### 2. CRITICAL — Unvalidated Array/List Access
**Verdict: PASS** — No `Array.get`, `List.nth`, `String.get`, or `.( )` indexed access. No array or list indexing at all.

### 3. CRITICAL — `Hashtbl.find` Without Guard
**Verdict: PASS** — Not used.

### 4. CRITICAL — Exception Raising
**Verdict: PASS** — No `failwith`, `raise`, `invalid_arg`, or `assert false`.

Two exception handlers, both narrow and correct:
- L48: `| exception Unix.Unix_error _ -> Missing` — caught and converted to structured result
- L59: `| exception Unix.Unix_error _ -> Missing` — same

### 5. CRITICAL — `Option.get` / `Option.unwrap`
**Verdict: PASS** — Not used.

### 6. CRITICAL — `List.hd` / `List.tl`
**Verdict: PASS** — Not used.

### 7. CRITICAL — Logic Errors
**Verdict: PASS** — No off-by-one, wrong comparison, or float equality issues.

Notable checks:
- L27: `VInt size when size >= 0` — correctly rejects negative sizes
- L229: `stats.Unix.st_size = expected_size` — integer equality, safe
- L285: `stats.Unix.st_size > 0` — correct for "non-empty"
- L89-97: `is_na_value v` is checked before `is_truthy v` — NA takes precedence, correct

### 8. WARNING — Dead Code
**Verdict: PASS** — All functions and variables are used:
- `assertion_failure` → used in all file-assertion builtins
- `path_arg` / `message_arg` → used in all path/message validation
- `expected_size_arg` → used by `assert_size_of_file`
- `optional_arity_error` → used in all builtin arity fallback paths

### 9. WARNING — Function Too Long (>80 lines)
**Verdict: NOTE** — `register` spans L83-306 (224 lines). This is long, but it follows the established codebase pattern of registering multiple builtins inline, each in its own `Env.add` block. Each inner function is short and focused (10-30 lines). Extracting to separate helper modules would be more idiomatic for a larger codebase but is consistent with existing practice here.

### 10. WARNING — Catch-all Exception Handlers
**Verdict: PASS** — No `with _ ->` catch-all patterns. The only exception handlers are narrow (`Unix.Unix_error _`).

### 11. INFO — Documentation / Style
**Verdict: NOTE**

- `--#` docstrings are present for all 5 user-facing functions (`assert`, `assert_file_exists`, `assert_dir_exists`, `assert_size_of_file`, `assert_non_empty_file`). Internal helpers (`assertion_failure`, `path_arg`, `message_arg`, `expected_size_arg`, `optional_arity_error`) correctly lack `--#` docs as they are not exported.
- The `optional_arity_error` function (L61-65) uses `%s` for the `expected` parameter, which produces slightly awkward grammar for values like `"1 or 2"`: e.g., "expects 1 or 2 arguments but received 0." This is a cosmetic issue.
- Function name strings (e.g., `"assert_file_exists"`) are repeated literally in each block's error messages. This is a minor DRY violation but follows the codebase convention.
- `inspect_file_target` and `inspect_directory_target` are structurally identical but operate on different `Unix.st_kind` variants — they are kept separate for type clarity, which is acceptable.

---

## Issues Found

None critical. One cosmetic grammar note (see §11, `optional_arity_error` string formatting).

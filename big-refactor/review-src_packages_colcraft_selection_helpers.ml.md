# Review: `src/packages/colcraft/selection_helpers.ml`

## Summary

**Score: 9.5/10** — Clean, well-structured file. Minor documentation organization issue.

---

## Checklist Results

### 1. CRITICAL — Partial Pattern Match (`Ast.value` constructors)
**Verdict: PASS** — No partial matches.

All match expressions are exhaustive:
- `matcher_of` (L9): `[(_, VDataFrame _)]`, `[(_, VVector _)]`, `_` catch-all
- `starts_with_impl` / `ends_with_impl` / `contains_impl` (L21-40): specific case + guard + catch-all
- `everything_impl` (L42): `[]` + `_`
- `type_predicate_impl` (L74): `[VVector _]`, `[_]`, `_`
- `matcher_builtin` (L89): `[(_, VDataFrame _)]`, `[(_, VVector _)]`, `_`
- `matches_impl` (L110): `[VString _]`, `_`
- `string_names_of_value` (L135): `VString`, `VVector`, `VList`, `_` catch-all
- `all_of_impl` / `any_of_impl`: `[_]`, `_`
- `where_impl` (L183): `[VBuiltin _]`, `[_]`, `_`

### 2. CRITICAL — Unvalidated Array/List Access
**Verdict: PASS** — No `Array.get`, `List.nth`, `String.get`, or `.( )` indexed access. All array operations use safe iteration (`Array.iter`, `Array.to_list`, `Array.fold_right`).

### 3. CRITICAL — `Hashtbl.find` Without Guard
**Verdict: PASS** — Not used.

### 4. CRITICAL — Exception Raising
**Verdict: PASS** — No `failwith`, `raise`, `invalid_arg`, or `assert false`.

The two exception handlers are safely scoped:
- L36-38: `match Str.search_forward ... with ... | exception Not_found -> false` — narrow, correct
- L114-116: `try Ok (Str.regexp ...) with Failure msg -> Error (...)` — narrow, converted to structured error

### 5. CRITICAL — `Option.get` / `Option.unwrap`
**Verdict: PASS** — Not used.

### 6. CRITICAL — `List.hd` / `List.tl`
**Verdict: PASS** — Not used.

### 7. CRITICAL — Logic Errors
**Verdict: PASS** — No off-by-one, wrong comparison, or float equality issues.

Notable check: `where_impl` at L196 calls `predicate.b_func [ (None, column_value) ] (ref Env.empty)`. This correctly calls the raw builtin function with a single named argument. The `make_builtin` wrapper that wraps `b_func` will strip the name, so the inner function receives `[column_value]` as intended. The fresh `Env.empty` environment means predicates relying on closure variables will not see them — this is consistent with dplyr semantics for `where()`.

### 8. WARNING — Dead Code
**Verdict: PASS** — All functions and variables are used:
- `matcher_of` → used by `starts_with_impl`, `ends_with_impl`, `contains_impl`, `everything_impl`
- `matcher_builtin` → used by `matches_impl`, `any_of_impl`, `where_impl`
- `string_names_of_value` → used by `all_of_impl`, `any_of_impl`
- `type_predicate_impl` → used in `register` for all four `is_*` predicates
- `bool_of_type_predicate` → used by `where_impl`

### 9. WARNING — Function Too Long (>80 lines)
**Verdict: PASS** — Longest function is `matches_impl` (24 lines). No function approaches 80 lines.

### 10. WARNING — Catch-all Exception Handlers
**Verdict: PASS** — All exception handlers are narrow (`Not_found`, `Failure msg`). No `with _ ->` catch-all patterns.

### 11. INFO — Documentation / Style
**Verdict: NOTE**

- `--#` docstring blocks (L202-312) are placed at the end of the file, above `register`, instead of adjacent to the function definitions they document. This is unconventional — docstrings for `starts_with`/`ends_with`/`contains`/`everything`/`where`/`matches`/`all_of`/`any_of` (L202-276) describe functions defined above (L21-200), while docstrings for `is_numeric`/`is_character`/`is_logical`/`is_factor` (L277-312) describe inline lambdas passed to `type_predicate_impl` in `register`. Consider moving `--#` blocks directly above each implementation for maintainability, or accept this as a stylistic convention of this codebase.
- Error messages are consistent and use the function name (e.g., `"Selection helper \`%s\` expects a DataFrame or Vector of names."`).
- No magic numbers or strings beyond function name literals.

---

## Issues Found

None critical. One minor documentation organization observation (see §11).

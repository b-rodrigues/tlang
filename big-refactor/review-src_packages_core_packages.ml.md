# Review: src/packages/core/packages.ml

**Lines**: 1002
**Severity summary**: 0 critical, 2 warning, 2 info

---

## WARNING: Unvalidated List.map2 usage

- **Line 795**: `List.map2 (fun old_name new_name -> ...) old_names new_names` — `List.map2` raises `Invalid_argument` when the two lists have different lengths. While `Arrow_table.column_names` and `Clean_colnames.clean_names` should preserve length in practice, there's no guard.

  **Fix**: Either add a length assertion before the call, or switch to `List.map2_exn` / wrap in try/with, or use `List.combine` which also raises but could be matched.

- **Line 797**: `Arrow_table.get_column arrow_table old_name` returns `Some col` for the match arm using `old_name`. The `old_names` and `new_names` lists are produced by different functions — a safety guard would prevent a subtle bug if they ever diverge.

  **Fix**: Same as above.

## WARNING: Internal make_builtin_named shadowing

- **Line 313**: `let make_builtin_named ?name ?(variadic=false) arity func = ...` shadows the module-level `make_builtin_named` from the eval/prelude. This creates a local variant that wraps named args differently (calls `Ast.Utils.unwrap_value` on each named argument's value).

  **Fix**: Rename to `make_builtin_named_wrapped` or similar to avoid confusion with the standard `make_builtin_named`.

## INFO: clean_colnames List.map2 unguarded

- **Lines 795–799**: Same `List.map2` concern as above. If `old_names` and `new_names` differ in length, the error message would be an OCaml `Invalid_argument` trace, not a T-language `VError`.

  **Fix**: Add explicit length validation before the call.

## INFO: source function reads 50 lines unconditionally

- **Lines 629–631**: `for _ = 1 to 50 do lines := input_line chan :: !lines done` — reads exactly 50 lines regardless of `doc.line_number`. Works because the file cursor is positioned at `doc.line_number` first, but this is a heuristics (50 lines of source), not a robust function-body extractor.

  **Fix**: Consider reading until a `;;` or blank-line terminator, or until end-of-file.

# Verification: src/packages/strcraft/string_ops.ml

## File: src/packages/strcraft/string_ops.ml

### Finding: Unreachable catch-all branch (Original line: 370)
**Actual line**: 370
**Status**: CONFIRMED
**Evidence**: Line 370: `| _ -> (* unreachable — guarded by outer match *) []` — the outer match on line 359 restricts `values` to `VDict _ | VList _`, so the `| _ ->` branch is indeed unreachable. The comment acknowledges this.
**Verdict**: The code correctly identifies this as unreachable. However, if the outer match is ever refactored to accept more types, this branch would silently return `[]` instead of triggering a compiler warning.
**Better fix**: Remove the catch-all branch. Use `| VDict d -> ... | VList items -> ...` which is already exhaustive for the narrowed type.

---

### Finding: Inconsistent error message format (Original line: 64, 76, 85, 88, 104, 122, 134, 284, 314, 331, 334, 370, 407, 423)
**Actual line**: 64, 76, 85, 88, 104, 122, 134, 284, 314, 331, 334, 407, 423
**Status**: CONFIRMED
**Evidence**:
- Line 64: `"is_empty expects a string."` (no `Function \`name\`` prefix)
- Line 76: `"str_substring expects (string, int, int)."` (no prefix)
- Line 85: `"Index out of bounds."` (no function name at all)
- Line 88: `"char_at expects (string, int)."` (no prefix)
- Line 104: `"index_of expects (string, string)."` (no prefix)
- Line 122: `"last_index_of expects (string, string)."` (no prefix)
- Line 134: `"contains expects (string, string)."` (no prefix)
- Line 284: Uses `Printf.sprintf` with function name but no `Function \`...\`` prefix
- Line 314: Same — no `Function \`...\`` prefix
- Line 331: `"str_repeat: count must be non-negative."` (colon separator, no function prefix)
- Line 334: `"str_repeat: result would exceed safety limit..."` (colon separator)
- Line 407-408: `"str_format expects a Dict or named List as the second argument, got %s"` (no function prefix)
- Line 423: `"length expects a collection..."` (no function prefix)
**Verdict**: The project convention (AGENTS.md rule 3) recommends `"Function \`fn_name\` expects ..."` format. Most of these functions don't follow this convention. The scalar helper functions don't receive the function name parameter needed to emit this format.
**Better fix**: Audit every error message and prefix with the function name using `Printf.sprintf "Function \`%s\` ..." function_name`.

---

### Finding: `slice` is an alias for `str_substring` (No Aliases rule) (Original line: 1080)
**Actual line**: 1080
**Status**: CONFIRMED
**Evidence**: `Env.add "slice" (make_builtin ~name:"slice" 3 substring_impl) env` — `slice` and `str_substring` (line 1079) share the exact same implementation (`substring_impl`). Per AGENTS.md: "Never create aliases for existing functions."
**Verdict**: This is a clear alias. The docstring block on lines 812-824 even explicitly says "Alias for `str_substring`."
**Better fix**: Remove the `slice` registration. Use `scripts/refactor_alias.sh slice str_substring` to update all references.

---

### Finding: `length` returning VError for VString is intentional type-checking (Original line: 415)
**Actual line**: 415
**Status**: FALSE_POSITIVE — review marked as INFO, not an issue
**Evidence**: The review itself states "This is an intentional design choice (strings are not collections). Not a bug."
**Verdict**: Not a finding to fix — the review correctly identifies this as intentional behavior.
**Better fix**: None needed.

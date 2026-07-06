# Review: src/packages/strcraft/string_ops.ml

**Lines**: 1109
**Severity summary**: 0 critical, 2 warning, 2 info

---

## WARNING: Unreachable catch-all branch

- **Line 370**: `| _ -> (* unreachable — guarded by outer match *) []`. The outer match on line 359 restricts `values` to `VDict _ | VList _`, so the `| _ ->` branch is indeed unreachable. However, if the outer match is refactored, this will silently return `[]` instead of producing a compiler warning.

  **Fix**: Remove the catch-all branch. Use `| VDict d -> ... | VList items -> ...` (already exhaustive for the narrowed type).

## WARNING: Inconsistent error message format

- **Line 64, 76, 85, 88, 104, 122, 134, 284, 314, 331, 334, 370, 407, 423**: Many scalar and top-level functions use inconsistent error message patterns:
  - `"is_empty expects a string."` (no `Function \`name\`` prefix)
  - `"str_repeat: count must be non-negative."` (colon separator)
  - `"str_lines expects a String or ShellResult, got %s"` (no function prefix)
  - `"str_format expects a Dict or named List as the second argument, got %s"` (no function prefix)

  The project convention (AGENTS.md) requires: `"Function \`fn_name\` expects ..."`

  **Fix**: Audit every error message and prefix with the function name using `Printf.sprintf "Function \`%s\` ..." function_name`.

## INFO: `slice` is an alias for `str_substring` (No Aliases rule)

- **Line 1080**: `Env.add "slice" (make_builtin ~name:"slice" 3 substring_impl) env` — `slice` and `str_substring` share the exact same implementation. Per AGENTS.md: "Never create aliases for existing functions."

  **Fix**: Remove the `slice` registration. Update any user-facing docs or test code that references `slice` to use `str_substring` instead.

## INFO: `length` returning VError for VString is intentional type-checking

- **Line 415**: `| [VString _] -> Error.type_error "length does not work on strings..."` — this is an intentional design choice (strings are not collections). Not a bug, but worth noting that it differs from the "vectorize or error" pattern used by other functions.

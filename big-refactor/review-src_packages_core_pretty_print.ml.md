# Review: src/packages/core/pretty_print.ml

**Lines**: 518
**Severity summary**: 0 critical, 1 warning, 2 info

---

## WARNING: Polymorphic equality on value type

- **Line 461**: `List.assoc "class" pairs = VString "summary"` — Uses polymorphic structural equality (`=`) on the `Ast.value` type. While `VString` is a simple variant and won't trigger issues with functional values (since `VString` contains only a plain string), this pattern is risky if the code is extended to compare against other variant constructors that _do_ embed functional values (e.g., `VBuiltin`, `VLambda`). Polymorphic equality on those would either raise `Invalid_argument` or return incorrect results.

  **Fix**: Use explicit pattern matching or a helper function for equality on `value`. For `VString` specifically, extract the string and compare with `String.equal`.

- **Line 463**: `is_visual_metadata_class (List.assoc "class" pairs)` — Same `List.assoc` pattern. The `is_visual_metadata_class` function does match on `VString` variants, so this is safe in practice.

  **Fix**: Same as above.

## INFO: List.assoc guarded by List.mem_assoc but fragile

- **Lines 461, 470**: The pattern `List.mem_assoc "class" pairs && List.assoc "class" pairs = ...` prevents `Not_found` exceptions, but this is a two-lookup pattern. Every call to `List.assoc` is preceded by a `List.mem_assoc` guard, which is safe but slightly redundant.

  **Fix**: Use `List.assoc_opt` for a single-lookup pattern.

## INFO: pretty_print_value (line 309) handles many cases but is manageable

- **Lines 309–492**: At 183 lines, `pretty_print_value` is a large function. However, it's a straightforward match on all the major `value` variants with each arm being self-contained. Refactoring would add complexity without much benefit.

  **Fix**: No action needed.

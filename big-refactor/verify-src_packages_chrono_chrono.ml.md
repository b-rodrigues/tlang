# Verification: src/packages/chrono/chrono.ml

## File: src/packages/chrono/chrono.ml

### Finding: Function too long — register (Original line: 1220-1665)
**Actual line**: 1220-1665
**Status**: CONFIRMED
**Evidence**: The `register` function spans 445 lines (1220 to 1665), containing ~50 inline helper definitions and ~50 `Env.add` calls. This is twice as long as the 80-line guideline.
**Verdict**: The file follows the project's convention of defining helpers inline near their registration site, which adds significant bulk. The function is well-structured with clear sections, but its length makes it harder to scan and maintain.
**Better fix**: Extract the inline helpers as top-level functions outside `register`, keeping `register` as a sequence of `Env.add` calls.

---

### Finding: Unvalidated Array index — month_abbrevs / month_names / weekday_abbrevs (Original lines: 495-497, 513, 1361)
**Actual line**: 495-497, 513, 1361
**Status**: CONFIRMED
**Evidence**: 
- Line 495: `month_abbrevs.(month - 1)` 
- Line 496: `month_names.(month - 1)`
- Line 497: `weekday_abbrevs.(wday - 1)`
- Line 513: `month_abbrevs.(month - 1)`
- Line 1361: `weekday_abbrevs.(base - 1)`
These array accesses assume `month` is in 1..12 and `wday` is in 1..7. The values come from `civil_from_days` and `sunday_wday_from_days` which guarantee this invariant, but a new code path producing out-of-range values would cause an uncaught `Invalid_argument`.
**Verdict**: The invariant is guaranteed by internal functions, but the code relies on this invariant without runtime enforcement.
**Better fix**: Guard with bounds checks or `Array.get_opt` (OCaml 5.1) that returns `VNA NAGeneric` on out-of-range.

---

### Finding: Inconsistent error message format for arithmetic operators (Original line: 459)
**Actual line**: 459
**Status**: CONFIRMED
**Evidence**: `Error.type_error "Date arithmetic expects a Date or Datetime value."` — this message does not include the `Function \`fn_name\`` prefix used by other functions in the package (e.g., line 533-534: `"Function \`%s\` unit must be one of..."`). The `add_period_to_value` function doesn't receive a function name parameter.
**Verdict**: The error message is less specific than it could be. The review correctly identifies the omission of the function name prefix.
**Better fix**: Thread `function_name` through `add_period_to_value` and use `"Function \`%s\` expects a Date or Datetime value."`.

---

### Finding: Magic number `7` for week_start default duplicated (Original line: 1353)
**Actual line**: 1353
**Status**: CONFIRMED
**Evidence**: `int_named_arg "week_start" 7 named_args` — the default `7` represents Sunday as start of week. It appears again implicitly in the same function body. This is a domain constant, not a truly arbitrary "magic number."
**Verdict**: The value `7` is a domain constant (Sunday = last day of week per many calendar systems). While a named constant would improve readability, this is low priority.
**Better fix**: Define `let default_week_start = 7` at the top of the file.

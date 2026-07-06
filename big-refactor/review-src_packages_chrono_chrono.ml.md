# Review: src/packages/chrono/chrono.ml

**Lines**: 1665
**Severity summary**: 0 critical, 2 warning, 2 info

---

## WARNING: Function too long — register

- **Line 1220-1665**: `register` is ~445 lines, containing ~50 inline helper definitions and `Env.add` calls. While this follows the project pattern of defining helpers close to their registration site, the sheer length makes it hard to review and maintain.

  **Fix**: Extract the inline helpers (`parse_date_result`, `parse_datetime_result`, `scalar_date_component`, `add_simple_parser`, `to_date_scalar`, `to_datetime_scalar`, etc.) as top-level functions outside `register`, and keep `register` as a sequence of `Env.add` calls only.

## WARNING: Unvalidated Array index — month_abbrevs / month_names / weekday_abbrevs

- **Line 495-497, 513, 1361**: `month_abbrevs.(month - 1)`, `month_names.(month - 1)`, `weekday_abbrevs.(wday - 1)`. These assume `month` is 1–12 and `wday` is 1–7, which is guaranteed by `civil_from_days` / `sunday_wday_from_days`. However, these are internal invariants not enforced by the type system. Adding a new code path that produces out-of-range values would cause an uncaught `Invalid_argument`.

  **Fix**: Guard with `Array.get_opt` (OCaml ≥ 5.1) or a bounds check that returns `VNA NAGeneric` on out-of-range input.

## INFO: Inconsistent error message format for arithmetic operators

- **Line 459**: `"Date arithmetic expects a Date or Datetime value."` — omits the `Function \`fn_name\`` prefix used elsewhere (e.g., line 533-534).

  **Fix**: Change to `"Function \`%s\` expects a Date or Datetime value."` and thread `function_name` through `add_period_to_value`.

## INFO: Magic number `7` for week_start default duplicated

- **Line 1353**: `int_named_arg "week_start" 7 named_args` — the default `7` (Sunday as start of week) appears in `wday` handling. This is a domain constant, not a magic number per se, but it's worth noting.

  **Fix**: Define `let default_week_start = 7` as a named constant at the top of the file (or reuse from `Ast`).

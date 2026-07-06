# Review: src/packages/math/acosh.ml
No issues found.

# Review: src/packages/math/acos.ml
No issues found.

# Review: src/packages/math/asinh.ml
No issues found.

# Review: src/packages/math/asin.ml
No issues found.

# Review: src/packages/math/atan2.ml
No issues found.

# Review: src/packages/math/atanh.ml
No issues found.

# Review: src/packages/math/atan.ml
No issues found.

# Review: src/packages/math/ceiling.ml
No issues found.

# Review: src/packages/math/cosh.ml
No issues found.

# Review: src/packages/math/cos.ml
No issues found.

# Review: src/packages/math/floor.ml
No issues found.

# Review: src/packages/math/math_common.ml
No issues found.

# Review: src/packages/math/pow.ml
No issues found.

# Review: src/packages/math/round.ml
No issues found.

# Review: src/packages/math/signif.ml
- No issues. Uses `Float.equal` for float comparisons (line 21, 37) — good.

# Review: src/packages/math/sign.ml
No issues found.

# Review: src/packages/math/sinh.ml
No issues found.

# Review: src/packages/math/sin.ml
No issues found.

# Review: src/packages/math/t_abs.ml
No issues found.

# Review: src/packages/math/tanh.ml
No issues found.

# Review: src/packages/math/tan.ml
No issues found.

# Review: src/packages/math/t_exp.ml
No issues found.

# Review: src/packages/math/t_iota.ml
No issues found.

# Review: src/packages/math/t_log.ml
No issues found.

# Review: src/packages/math/trunc.ml
No issues found.

# Review: src/packages/math/t_sqrt.ml
No issues found.

# Review: src/tdoc/tdoc_json.ml
- **WARNING**: `from_string` (line 13-18) raises custom `Json_error` exception on parse failure. Per codebase rules ("No raw OCaml exceptions in user-facing paths"), this function should return a `result` type rather than raising. Callers in `tdoc_registry.ml` do catch it, but the function signature forces exception-based error handling on all callers.
- No other issues.

# Review: src/tdoc/tdoc_markdown.ml
No issues found.

# Review: src/tdoc/tdoc_parser.ml
- **WARNING**: `extract_comments` (line 29-39) calls `open_in filename` (line 31) without a try/with for `Sys_error`. If the file does not exist, this raises an uncaught `Sys_error` exception to the caller. `parse_file` (line 157) does not wrap the call either, so this propagates outward.
- **WARNING**: Dead code at line 36: `[] (* unreachable *)` — placed after an infinite `while true` loop, confirmed unreachable by the comment and the `End_of_file` handler.
- No other issues.

# Review: src/tdoc/tdoc_registry.ml
- **WARNING**: Catch-all exception handler at line 82 (`| exn ->`) in `load_from_json`. While it prints a warning message, a catch-all is a red flag per code review checklist — should match specific exceptions where possible.
- **INFO**: Global mutable registry state at line 6 (`Hashtbl.t`). Acceptable for a tool-internal design, but noted.
- **INFO**: `to_json_file` (line 30-35) calls `open_out filename` without exception handling — could raise `Sys_error` if the output path is unwritable.
- No other issues.

# Review: src/tdoc/tdoc_types.ml
No issues found.

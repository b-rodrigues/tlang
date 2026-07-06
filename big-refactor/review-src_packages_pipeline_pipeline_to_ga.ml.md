# Review: src/packages/pipeline/pipeline_to_ga.ml

**Lines**: 198
**Severity summary**: 0 critical, 2 warnings, 0 info

---

## WARNING: Catch-all exception handler in get_project_name

- **Line 17**: `with _ -> None` in `get_project_name`. If `really_input_string`, `Toml_parser.parse_tproject_toml`, or any IO operation throws an unexpected exception (e.g., `Unix_error`, `Sys_error`, `Failure`), it is silently swallowed and the function returns `None`.

  **Fix**: Only catch `Sys_error` for file-not-found scenarios and let unexpected exceptions propagate. Alternatively, log the error before returning `None`:
  ```ocaml
  with Sys_error _ -> None
  ```

---

## WARNING: Function too long (ga_fn)

- **Line 105-196**: `ga_fn` is ~91 lines with deeply nested validation logic for three arguments (`pipeline_script`, `name`, `file`), each requiring its own `result` type validation with descriptive error messages. The nesting reaches 6 levels deep.

  **Fix**: Extract argument validation into three separate helper functions `validate_pipeline_script`, `validate_name`, `validate_file`, each returning `(string, error) result`. This would flatten the main function to a clean pipeline:
  ```ocaml
  let* script = validate_pipeline_script named_args in
  let* name = validate_name named_args in
  let* file = validate_file name named_args in
  ...
  ```

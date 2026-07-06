# Review: src/package_manager/toml_parser.ml

**Lines**: 328
**Severity summary**: 0 critical, 4 warning, 2 info

---

## WARNING: Pervasive catch-all exception handlers (`with _ ->`)

The file uses catch-all `with _ ->` extensively. While many of these are intentional "get with default" semantics, they collectively mask real errors (type mismatches, schema violations, `Otoml` internal failures) and make debugging difficult.

- **Line 9**: `get_string_opt` — `try Otoml.find toml Otoml.get_string path with _ -> default`
  Catches ALL exceptions, including `Otoml.Type_error`, `Not_found`, and system errors. A user writing a string value as a number (e.g. `version = 1.0`) will silently get an empty-string default.

  **Fix**: Catch only `Not_found` and `Otoml.Type_error` specifically:
  ```ocaml
  try Otoml.find toml Otoml.get_string path
  with
  | Not_found -> default
  | Otoml.Type_error _ -> default
  ```

- **Line 14**: `get_string_list_opt` — Same pattern as above; same fix.

- **Lines 136–137**: `let cran_inputs = try Otoml.find value (Otoml.get_array Otoml.get_string) ["deps"] with _ -> [] in`
  Catch-all within `parse_r_git_dependencies`. A malformed `deps` value (e.g. a string instead of an array) is silently treated as empty.

  **Fix**: Catch specific exceptions only.

- **Lines 140–141**: `let subdir = try Some (Otoml.find value Otoml.get_string ["subdir"]) with _ -> None in`
  Same pattern.

- **Line 150**: Inner `with _ ->` in `parse_r_git_dependencies` catches the diagnostic `Printf.eprintf` warning, then returns `None`. If an unexpected exception occurs here (e.g. stack overflow), it is caught and treated as "missing required git/rev fields".

  **Fix**: Narrow the inner `with` to `Not_found` and expected type errors.

- **Line 173–174**: `let py_version_explicit = try Some (Otoml.find toml Otoml.get_string ["py-dependencies"; "version"]) with _ -> None in`
  Same pattern.

- **Line 20–33**: `read_requires_python_from_workspace` has nested catch-alls. The outer `with _ -> None` hides parse errors from the pyproject.toml file.

- **Line 86–97**: `parse_dependencies` uses a catch-all `with _ -> None` on each key-value pair, which silently drops entries whose `git` or `tag` fields are missing.

---

## WARNING: `parse_r_git_dependencies` — nested `try/with` with overlapping catch-all scopes creates error-handling confusion

- **Lines 127–155**: The function has `try` at line 127, then an inner `try` at line 132, each with `with _ ->`. The inner catch-all prints a warning and returns `None`. The outer catch-all also returns `None`. If the `Otoml.get_table value` check at line 131 succeeds but the inner field accesses fail (expected), the warning fires. But if `Otoml.get_table value` fails (e.g. the value is a string, not a table), the outer catch-all silently returns `None` with no warning.

  **Fix**: Restructure to avoid nested try/with. Warn on expected skips; let unexpected errors propagate.

---

## WARNING: `parse_tproject_toml` is 76 lines long and does too much

- **Lines 159–235**: The function parses every section of `tproject.toml`, infers Python versions, warns about version conflicts, and validates resolver settings. This should be decomposed.

  **Fix**: Extract helpers:
  - `parse_py_dependencies toml ~root_dir` (lines 165–206)
  - `parse_r_dependencies toml` (lines 207–209)
  - `parse_project_metadata toml` (lines 162–163, 211–231)

---

## WARNING: Hard-coded default Python version `"python314"`

- **Line 190**: When `py_resolver = "nixpkgs"` and no explicit version is set, the default is `"python314"`. This will become stale as Nixpkgs advances beyond Python 3.14. It is a magic string.

  **Fix**: Read from a constant (`let default_py_version = "python314"`) with a comment explaining the policy, or make it configurable.

---

## INFO: `parse_dependencies` only supports `git` + `tag` dependencies

- **Lines 86–97**: The `[dependencies]` parser only recognizes entries with `git` and `tag` fields. Any other dependency spec (path, version, url) is silently dropped.

  **Fix**: Document this limitation or extend to support a `version` field for non-git dependencies.

---

## INFO: `parse_description_toml` silently sets empty-string defaults for missing fields

- **Lines 108–109**: If `authors` or `description` are missing, they default to `""` or `[]`. This is OK for optional fields, but the validation of `name` being non-empty is the only hard check. Missing `version`, `license`, etc. produce no warning.

  **Fix**: Add missing-field warnings or default-value logging to help users diagnose misconfigured package files.

# Review: src/packages/pipeline/build_log.ml

**Lines**: 609
**Severity summary**: 0 critical, 4 warnings, 2 info

---

## WARNING: Catch-all exception handlers silently swallowing errors

- **Line 242**: `with _ -> ()` in `collect_exceptions_fn`. The entire Yojson JSON processing loop (lines 170–241) is wrapped in a try block that catches **all** exceptions and discards them. This means if any node in the build log has malformed JSON, the entire error collection silently returns an empty list with no indication of failure.

  **Fix**: Log the exception (even at debug level) before swallowing, or at minimum catch only specific Yojson exceptions (`Yojson.Json_error`, `Type_error`). Consider collecting per-node errors individually so one bad node doesn't kill the whole function.

- **Line 380**: `with _ -> ()` in `build_log_history_fn` (lines 362–380). Same pattern — all JSON parsing and processing errors for a build log entry are silently discarded. Individual entries that fail parsing are skipped with no warning.

  **Fix**: Same as above — log the exception or catch specific types.

---

## WARNING: Function too long (collect_exceptions_fn)

- **Line 156-262**: `collect_exceptions_fn` is ~106 lines with deeply nested logic for JSON parsing, error/warning extraction, and DataFrame construction.

  **Fix**: Extract the per-node error extraction into a helper `extract_node_errors(node_json)`, the warning extraction into `extract_node_warnings(node_json, path)`, and the DataFrame construction into a reusable helper that other functions also use.

---

## WARNING: Function too long (build_log_history_fn)

- **Line 284-446**: `build_log_history_fn` is ~162 lines. It handles argument parsing, regex matching, log traversal, JSON parsing, stats extraction, and DataFrame construction all in one function.

  **Fix**: Extract log-path matching/filtering into `filter_log_paths(p, ?pattern, ?limit)`, per-log JSON stats extraction into `extract_build_stats(log_path)`, and DataFrame assembly into a separate helper.

---

## WARNING: Function too long (node_diff_fn)

- **Line 481-597**: `node_diff_fn` is ~116 lines with a ~60-line inner function `load_artifact`. The inner function handles log resolution (by name, index, or regex), artifact loading, and native-object preservation — three distinct concerns.

  **Fix**: Extract `load_artifact` to a top-level function, and split log resolution (`resolve_log_path`) from artifact deserialization (`load_artifact_value`).

---

## INFO: `List.nth` with bounds guard (safe but fragile)

- **Line 373**: `List.nth parts 2` and `List.nth parts 3` inside `if List.length parts >= 4 then ...`. While this is correctly guarded, `List.nth` on a dynamically-derived list is a maintenance hazard — if the filename format changes, the length check and index access could drift apart.

  **Fix**: Use pattern matching on the list to extract elements, which is statically checked:
  ```ocaml
  match parts with
  | _ :: _ :: ts1 :: ts2 :: _ -> ...
  | _ -> ""
  ```

---

## INFO: Local `make_builtin_named` redefinition

- **Line 600-602**: A local `make_builtin_named` helper is defined inside `register`. If a global version of this function exists in the environment, this shadows it. The function also dereferences `!Ast.meta_pipeline_flatten_resolver`, which is a mutable reference — its state could change between definition and invocation.

  **Fix**: Use the canonical `make_builtin_named` from the environment if one exists, or document why this local variant with `meta_pipeline_flatten_resolver` is necessary.

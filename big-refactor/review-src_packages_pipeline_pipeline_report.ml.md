# Review: src/packages/pipeline/pipeline_report.ml

**Lines**: 687
**Severity summary**: 0 critical, 3 warning, 1 info

---

## WARNING: Very long closure — `report_fn` inside `register`

- **Lines 458–686**: 228-line anonymous function handling argument parsing, log matching, node classification, and both Markdown and HTML report generation. This single function is ~33% of the entire file.

  **Fix**: Extract Markdown generation (lines 556–675) and HTML generation (lines 545–554) into named helper functions. Extract the file-path resolution logic (lines 493–515) into a separate function. Consider moving `generate_html_report` and the Markdown generation logic out of the closure entirely and passing the builder environment as parameters.

## WARNING: Broad exception handler in `register`

- **Line 678**: `with e -> Error.make_error RuntimeError ...` wraps essentially the entire report generation logic (lines 519–677) in a catch-all exception handler. While this preserves the `VError` contract, it can mask bugs like pattern-match failures or misused `Yojson.Safe.Util` accessors.

  **Fix**: Narrow the `try` block to only the I/O and JSON-parsing operations (lines 524–536), not the entire classification and rendering logic. Use specific exception handlers (`Sys_error`, `Yojson.Json_error`) where possible.

## WARNING: `Filename.concat` on potentially relative directory path

- **Line 200-202**: `Filename.concat (Filename.dirname path) "warnings"` used to locate warnings files from build log entries. If `path` has no directory component, `Filename.dirname path` returns `"."`, causing `parse_node_warnings` to search in the current working directory.

  **Fix**: Resolve `path` against `Builder.pipeline_dir` before computing the warnings path, or validate that `path` is absolute.

## INFO: `Yojson.Safe.Util` accessors can raise on unexpected JSON structure

- **Lines 43–57**: Uses `to_list`, `to_string`, `member`, `to_bool` etc. from `Yojson.Safe.Util`, which raise `(Type_error ...)` if the JSON structure doesn't match. These are caught by the outer `try/with` (line 39) that handles `Yojson.Json_error` and any exception `e`. However, the `Type_error` from these accessors is not a `Yojson.Json_error` — it's caught by the generic `| e ->` branch. Consider catching `Yojson.Safe.Util.Type_error` explicitly.

  **Fix**: Add `| Yojson.Safe.Util.Type_error (msg, _) ->` as a specific handler in the `read_build_log_entries` function at line 61.

# Verification: src/packages/pipeline/pipeline_report.ml

## File: src/packages/pipeline/pipeline_report.ml

### Finding: Very long closure — `report_fn` inside `register` (Original line: 458-686)
**Actual line**: 458-686
**Status**: CONFIRMED
**Evidence**: The `report_fn` closure inside `register` spans 228 lines (458-686). It handles argument parsing, log matching, node classification, and both Markdown and HTML report generation — all inside a single `VBuiltin` anonymous function.
**Verdict**: At 228 lines, this is ~33% of the file in a single function. Breaking it into named helpers would improve maintainability.
**Better fix**: Extract Markdown generation, HTML generation, and file-path resolution into named helper functions.

---

### Finding: Broad exception handler in `register` (Original line: 678)
**Actual line**: 678
**Status**: CONFIRMED
**Evidence**: `with e -> Error.make_error RuntimeError (Printf.sprintf "Unexpected error generating pipeline report: %s" (Printexc.to_string e))` — wraps the entire report generation logic (lines 519-677) in a catch-all exception handler.
**Verdict**: This preserves the `VError` contract but is overly broad. It wraps the classification and rendering logic (lines 538-543, 556-676) which don't do I/O and shouldn't fail. The `try` block on line 519 starts at the beginning of the file writing logic, when only the I/O and JSON operations on lines 524-536 need protection.
**Better fix**: Narrow the `try` block to only the I/O and JSON-parsing operations. Use specific exception handlers for `Sys_error` and `Yojson.Json_error` where possible.

---

### Finding: `Filename.concat` on potentially relative directory path (Original line: 200-202)
**Actual line**: 200-202
**Status**: CONFIRMED
**Evidence**: `Filename.concat (Filename.dirname path) "warnings"` — if `path` has no directory component (e.g., just a filename), `Filename.dirname path` returns `"."`, causing `parse_node_warnings` to search in the current working directory.
**Verdict**: This could cause incorrect behavior when the path is relative. The current code relies on paths being absolute (which is likely the case in practice for Nix build artifacts), but the code doesn't enforce this.
**Better fix**: Resolve `path` against `Builder.pipeline_dir` before computing the warnings path.

---

### Finding: `Yojson.Safe.Util` accessors can raise on unexpected JSON structure (Original lines: 43-57)
**Actual line**: 43-57
**Status**: CONFIRMED
**Evidence**: `to_list`, `to_string`, `member`, `to_bool` from `Yojson.Safe.Util` raise `Type_error` when the JSON structure doesn't match. However, the `Type_error` from these accessors is caught by the generic `| e ->` branch on line 62, not by the `Yojson.Json_error` handler on line 61.
**Verdict**: The error handling works (the generic catch-all catches it), but a specific handler for `Yojson.Safe.Util.Type_error` would provide better error messages.
**Better fix**: Add `| Yojson.Safe.Util.Type_error (msg, _) ->` as a specific handler in the `read_build_log_entries` function.

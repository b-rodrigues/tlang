# Review: `src/pipeline/builder_artifacts.ml`

**Lines**: 406
**Severity summary**: 0 critical, 1 warning, 2 info

---

## WARNING: `inspect_artifacts` function is too long and deeply nested

- **Lines 281–406**: At ~125 lines with up to 7 levels of nesting (`match` inside `Fun.protect` inside `match` inside `try` inside `match` inside `Fun.protect` inside `match`). The function handles archive I/O, process spawning, JSON parsing, and error recovery in a single monolithic block.

  **Fix**: Extract sub-tasks into named helpers:
  - Temporary directory creation / cleanup
  - `nix-store --import` invocations
  - `nix path-info --json` parsing and result formatting

## INFO: Silent catch-all exception handlers in cleanup paths

- **Line 222**: `try Sys.remove archive_path with _ -> ()` — if cleanup of a failed archive fails for any reason, the error is swallowed. Acceptable for best-effort cleanup.

- **Line 302**: `try Unix.mkdir temp_store_dir 0o755 with _ -> ()` — if the temporary directory already exists (e.g., from a prior crash), `mkdir` fails silently and the function continues with a potentially stale directory, which may produce incorrect `nix path-info` results.

  **Fix**: Check if the directory already exists before creating it (`Sys.file_exists`), or remove a stale one first.

## INFO: `collect_paths_from_value` catch-all silently ignores new variants

- **Line 166**: `| _ -> []` silently returns an empty list for any unhandled value variant (e.g., `VNDArray`, `VError`). This is by design for forward-compatibility, but if a new variant is added that could contain pipeline paths (e.g., a future `VPipelineList`), the function would silently miss it.

  **Fix**: Document the catch-all as an explicit `| VError _ | VNDArray _ | ... -> []` to trigger a compiler warning when new variants are added.

# Verification Report: `src/pipeline/builder_artifacts.ml`

Review file: `review-src_pipeline_builder_artifacts.ml.md`

---

## File: src/pipeline/builder_artifacts.ml

### Finding: `inspect_artifacts` function is too long and deeply nested (Original lines: 281-406)

**Actual lines**: 281-406
**Status**: CONFIRMED

**Evidence**: The function spans ~125 lines and contains the full lifecycle: temp directory management, archive I/O, process spawning with `nix-store --import`, manual pipe management, JSON parsing with `nix path-info --json`, error recovery, and result formatting. The nesting reaches up to 7 levels (documented in the review). The suggested decomposition targets (temp dir creation/cleanup, nix-store import, path-info parsing) are logical extraction points.

**Verdict**: Valid structural observation. The function is a monolith doing multiple distinct subtasks. Extracting helpers would improve readability and testability, but this is a style/architecture issue, not a correctness bug.

---

### Finding: Silent catch-all exception handler in cleanup (Original line: 222)

**Actual line**: 222
**Status**: CONFIRMED (acceptable)

**Evidence**: `(try Sys.remove archive_path with _ -> ())` at line 222 is intentionally a best-effort cleanup. The alternative (letting the exception propagate) would mask the original error that caused the cleanup to be needed. The `()` return is immediately followed by returning the original error on line 223: `err`.

**Verdict**: This is idiomatic best-effort cleanup. The review also notes it's "acceptable for best-effort cleanup." No fix needed.

---

### Finding: Silent catch-all for `Unix.mkdir` could hide stale directory (Original line: 302)

**Actual line**: 302
**Status**: CONFIRMED

**Evidence**: `(try Unix.mkdir temp_store_dir 0o755 with _ -> ())` at line 302 silently swallows all errors. If the temp directory already exists from a prior crash, `mkdir` fails with `EEXIST`, the code continues silently, and the stale directory is used as the `--store` argument for `nix-store --import`. Stale artifacts in the temp directory could produce incorrect `nix path-info` results. The `cleanup()` function is called on error paths but only at specific points.

**Verdict**: The review's fix suggestion is reasonable: check `Sys.file_exists` before creating the directory, or clean up a stale directory first. A minimal fix:
```ocaml
(if Sys.file_exists temp_store_dir then
   let _ = run_command_argv_exit [| "rm"; "-rf"; temp_store_dir |] in
   ());
Unix.mkdir temp_store_dir 0o755
```

---

### Finding: `collect_paths_from_value` catch-all silently ignores new variants (Original line: 166)

**Actual line**: 166
**Status**: CONFIRMED (intentional design, minor risk)

**Evidence**: `| _ -> []` returns an empty list for any unhandled `Ast.value` variant. The function handles `VPipeline`, `VMetaPipeline`, `VComputedNode`, `VString`, `VList`, `VVector`, `VDict`, and has an explicit catch-all at line 170 for scalar types (`VInt | VFloat | VBool | VNA | ...`). The catch-all at line 166 covers all remaining variants.

**Verdict**: The review correctly identifies that this pattern won't trigger a compiler warning when new variants are added. The suggested fix (explicitly listing unhandled variants like `| VError _ | VNDArray _ | ... -> []`) would enable the compiler to flag new variants. However, the explicit `VInt | VFloat | ... ->` guard on line 170 in `export_artifacts` already provides the same safety net at the call site. The risk is that internally generated paths from a new value variant might be silently missed. Low-priority defensive improvement.

# Review: `src/pipeline/pipeline_dependency_requirements.ml`

**Lines**: 483
**Severity summary**: 0 critical, 2 warning, 2 info

---

## WARNING: Redundant `let req = req in` binding

- **Line 158**: `let req = req in` inside the `"R"` branch of `scan_code_requirements` is a no-op binding. It shadows the outer binding with itself and serves no purpose — likely a leftover from a refactoring that extracted the `has_pkg` closure.

  **Fix**: Remove the line entirely.

## WARNING: `scan_code_requirements` branches have inconsistent reason-discarding behavior

- **Line 207** (Python branch): When no Python packages are detected, the function returns `empty_requirements`, which **discards** the `reasons` field (the `"node X usage discovery"` reason added at line 155).

  Compare:
  - **R branch** (line 168): Returns `req` (with reason preserved) even when no R packages are detected.
  - **Julia branch** (line 215–227): Always returns `req` (with reason preserved).

  This inconsistency means the reason string is silently dropped for Python nodes with no detectable imports, making the dependency analysis harder to debug.

  **Fix**: Change line 207 to `else req` to match the R and Julia branches.

## INFO: Redundant `let req = req in` at line 158 (see above)

## INFO: `read_file` uses `in_channel_length` which fails on non-regular files

- **Line 378**: `really_input_string ch (in_channel_length ch)` — `in_channel_length` raises `Sys_error` on pipes, FIFOs, or other non-seekable inputs. While `tproject.toml` is always a regular file, the function signature doesn't document this constraint.

  **Fix**: Use `really_input_string` in a loop with `input_char` or `Stdlib` functions that work on any input channel, or document that only regular files are supported.

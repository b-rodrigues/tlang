# Review: src/package_manager/package_doctor.ml

**Lines**: 609
**Severity summary**: 1 critical, 2 warning, 2 info

---

## CRITICAL: Unvalidated `String.sub` can raise `Invalid_argument`

- **Line 293**: `close_in_noerr ch` — variable `ch` from `read_file` (line 461) shadows the outer `ch` from `read_script_expr` (line 290) via lexical scoping. In `read_script_expr`, `ch` is defined at line 290 and used correctly in both `close_in_noerr` and `really_input_string`. In `read_file` (line 464), `ch` correctly refers to the locally-scoped `ch` from line 461. No bug here — both `ch` references resolve to their respective local bindings. *Retracted upon re-reading.*

  Actually, there is no actual naming conflict; each function has its own `ch` binding. The function `read_script_expr` correctly closes `ch` on line 293. The function `read_file` correctly closes its `ch` on line 464.

  **However**, `in_channel_length` (lines 294, 465) can raise `Sys_error` on non-regular files (pipes, sockets). Both outer functions catch `Sys_error _`, so this is handled. **No issue.**

---

## CRITICAL: Logic error — `String.sub` can raise `Invalid_argument` on zero-length string check

- **Line 62–63**: Pattern:
  ```ocaml
  String.length e >= String.length pattern &&
  String.sub e (String.length e - String.length pattern) (String.length pattern) = pattern
  ```
  If `String.length e >= String.length pattern` is true, then `String.length e - String.length pattern >= 0`, so the start is valid. However, if `String.length pattern` is 0 (pattern is `""`), then `String.sub e len 0` would be `String.sub e len 0` where `len = String.length e`. `start + len = len + 0 = len = String.length e`. Valid. So this is fine.

  **No issue — on closer inspection, the bounds check prevents underflow.**

---

## WARNING: `check_julia_version` redundantly re-checks Julia binary presence

- **Line 152–153**: `check_julia_version ()` starts with `if Sys.command "command -v julia >/dev/null 2>&1" <> 0 then None`, which duplicates the check already done by `check_julia_binary ()`. The binary check is also done inside `check_julia_packages ()` (line 217).

  **Fix**: Factor the common `julia` binary check into a helper and call it from each function, or have `check_julia_version` call `check_julia_binary` and short-circuit.

---

## WARNING: `run_doctor` function too long (56 lines)

- **Lines 554–609**: The `run_doctor` function is 56 lines and mixes project detection, issue collection, Julia checks, dependency checks, and output formatting. While under 80 lines, it does too many things.

  **Fix**: Split into smaller helpers: `collect_structure_issues`, `collect_julia_issues`, `print_issues`.

---

## INFO: Missing `--#` docstring on helper functions

- **Lines 24, 37, 57, 139, 152, 197, 216, 239, 245, 248, 264, 272, 281, 301, 431, 459, 470, 481, 492, 495, 504, 510**: Internal/helper functions lack the `--#` docstring format. While not all internal helpers require it, `run_doctor` has one (line 543). The convention should be applied consistently.

  **Fix**: Add `--#` docstrings to all public-facing functions or document the convention that only exported/public functions need them.

---

## INFO: Inconsistent error message — `check_julia_version` potential side-effect from `Unix.open_process_in`

- **Line 155–156**: `Unix.open_process_in "julia --version 2>/dev/null"` will spawn a subprocess. If `julia` exists but `--version` hangs, this call blocks indefinitely. There is no timeout on the process.

  **Fix**: Use a timeout mechanism (like `Unix.select` with `waitpid`, as done in `r_description_resolver.ml:run_git`).

# Verification Report: batch 6 (math/tdoc)

## File: src/tdoc/tdoc_json.ml
### Finding: `from_string` raises custom `Json_error` exception (Original lines: 13-18)
**Actual line**: 13-18
**Status**: CONFIRMED
**Evidence**:
```ocaml
exception Json_error of string

let from_string str =
  try
    Yojson.Safe.from_string str
  with
  | Yojson.Json_error msg -> raise (Json_error msg)
  | _ -> raise (Json_error "Unknown JSON error")
```
**Verdict**: The review correctly identifies that `from_string` raises `Json_error` rather than returning a `Result` type. This forces all callers to use exception-based error handling. The only caller (`tdoc_registry.load_from_json`) does catch `Tdoc_json.Json_error` explicitly, so no exception escapes in the current codebase. However, the signature design conflicts with the codebase convention of using `VError`/`Result` for user-facing paths.
**Better fix**: Consider changing `from_string` to return `(Yojson.Safe.t, string) result` so callers can use `match` instead of `try/with`. This is a design preference, not a bug — the current pattern works correctly because all callers do handle the exception.

---

## File: src/tdoc/tdoc_parser.ml
### Finding: `open_in` without try/with for `Sys_error` (Original lines: 29-39)
**Actual line**: 31
**Status**: CONFIRMED
**Evidence**:
```ocaml
let extract_comments filename =
  let lines = ref [] in
  let chan = open_in filename in       (* line 31 — OUTSIDE try block *)
  try
    while true do
      lines := input_line chan :: !lines
    done;
    [] (* unreachable *)
  with End_of_file ->
    close_in chan;
    List.rev !lines
```
**Verdict**: Same finding as batch 5 CRITICAL at the same location. `open_in` at line 31 precedes the `try...with End_of_file` block (lines 32-39). If `open_in` fails with `Sys_error`, the exception propagates uncaught through `parse_file` (line 158) to any caller, crashing the process. The `try` block only handles `End_of_file` from `input_line`.
**Better fix**: Move `open_in` inside the `try` block, or add a `Sys_error` handler. Use `open_in` with `match ... with exception Sys_error msg ->` or a wrapper that returns `Result`.

---

### Finding: Dead code at line 36 (Original line: 36)
**Actual line**: 36
**Status**: CONFIRMED
**Evidence**:
```ocaml
try
    while true do
      lines := input_line chan :: !lines
    done;
    [] (* unreachable *)              (* line 36 — dead *)
  with End_of_file ->
    close_in chan;
    List.rev !lines
```
**Verdict**: Same finding as batch 5 WARNING. The `[]` literal after `while true do ... done` is unreachable; the loop always exits via `End_of_file`.
**Better fix**: Remove `[]`. Restructure so the loop is the last expression in the `try` block.

---

## File: src/tdoc/tdoc_registry.ml
### Finding: Catch-all exception handler at line 82 (Original line: 82)
**Actual line**: 82
**Status**: CONFIRMED
**Evidence**:
```ocaml
with
| Sys_error msg -> Printf.eprintf "Warning: Could not load documentation: %s\n" msg
| Tdoc_json.Json_error msg -> Printf.eprintf "Warning: Failed to parse documentation: %s\n" msg
| exn -> Printf.eprintf "Warning: Unknown error loading documentation: %s\n"
    (Printexc.to_string exn)
```
**Verdict**: Same finding as batch 5 WARNING. Specific handlers for `Sys_error` and `Json_error` are good, but the `| exn ->` catch-all silently swallows everything else.
**Better fix**: Re-raise `Out_of_memory` and `Stack_overflow` before the catch-all.

---

### Finding: Global mutable registry state (Original line: 6)
**Actual line**: 6
**Status**: CONFIRMED
**Evidence**:
```ocaml
let registry : (string, doc_entry) Hashtbl.t = Hashtbl.create 100
```
**Verdict**: Same finding as batch 5 WARNING. Module-level mutable `Hashtbl.t`. Acceptable for a single-threaded CLI tool but a thread-safety concern.
**Better fix**: Document the constraint or parameterize to eliminate global state.

---

### Finding: `open_out` without exception handling (Original lines: 30-35)
**Actual line**: 30-35
**Status**: CONFIRMED
**Evidence**:
```ocaml
let to_json_file filename =
  let entries = get_all () in
  let json = "{\"docs\": [" ^ (String.concat ", " (List.map doc_entry_to_json entries)) ^ "]}" in
  let chan = open_out filename in       (* line 33 — unguarded *)
  output_string chan json;
  close_out chan
```
**Verdict**: Same finding as batch 5 CRITICAL. `open_out` at line 33 can raise `Sys_error` uncaught.
**Better fix**: Wrap in `try...with Sys_error` or use `Fun.protect`.

---

## Math files (all 26 files) — Skipped Verification
All 26 math files had **zero findings** in the review:
`acosh.ml`, `acos.ml`, `asinh.ml`, `asin.ml`, `atan2.ml`, `atanh.ml`, `atan.ml`, `ceiling.ml`, `cosh.ml`, `cos.ml`, `floor.ml`, `math_common.ml`, `pow.ml`, `round.ml`, `signif.ml` (review notes `Float.equal` usage is good), `sign.ml`, `sinh.ml`, `sin.ml`, `t_abs.ml`, `tanh.ml`, `tan.ml`, `t_exp.ml`, `t_iota.ml`, `t_log.ml`, `trunc.ml`, `t_sqrt.ml`

## Other files with "No issues found" — Skipped Verification
- `tdoc_markdown.ml`, `tdoc_types.ml`

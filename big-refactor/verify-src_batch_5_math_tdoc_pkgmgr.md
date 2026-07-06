# Verification Report: batch 5 (math/tdoc/pkgmgr)

## File: src/tdoc/tdoc_parser.ml
### Finding: `open_in` unguarded against `Sys_error` (Original line: 31)
**Actual line**: 31
**Status**: CONFIRMED
**Evidence**:
```ocaml
let extract_comments filename =
  let lines = ref [] in
  let chan = open_in filename in       (* line 31 — BEFORE try block *)
  try
    while true do
      lines := input_line chan :: !lines
    done;
    [] (* unreachable *)              (* line 36 *)
  with End_of_file ->
    close_in chan;
    List.rev !lines
```
**Verdict**: `open_in` is on line 31, **outside** the `try` block (which starts on line 32). The `try...with End_of_file` on lines 32-39 only catches `End_of_file` from `input_line` inside the loop. If `filename` doesn't exist or is unreadable, `open_in` raises `Sys_error` which propagates uncaught to `parse_file` (line 158) and then to the caller. This is a user-facing API entry point (`parse_file`), so an uncaught `Sys_error` crashes the program.
**Better fix**: Move `open_in` inside the `try` block, or wrap with `try...with Sys_error msg -> Error.make_error FileError msg`. Alternatively, use `open_in` inside `Fun.protect` or inside a `match...with exception` pattern.

---

### Finding: Dead code after infinite loop (Original lines: 34-36)
**Actual line**: 36
**Status**: CONFIRMED
**Evidence**:
```ocaml
try
    while true do
      lines := input_line chan :: !lines
    done;
    [] (* unreachable *)              (* line 36 *)
  with End_of_file ->
    close_in chan;
    List.rev !lines
```
**Verdict**: The `[]` literal on line 36 after `while true do ... done` is dead code. The `while true` loop can only exit via the `End_of_file` exception handler, which correctly returns `List.rev !lines`. The `[]` is never reached and the comment acknowledges this.
**Better fix**: Remove the `[]` literal. One way: restructure to use `match ... with exception End_of_file ->` or change the `try` placement so the loop is the last expression in the `try` block.

---

## File: src/tdoc/tdoc_registry.ml
### Finding: `open_out` unguarded against `Sys_error` (Original line: 34)
**Actual line**: 30-35 (function body)
**Status**: CONFIRMED
**Evidence**:
```ocaml
let to_json_file filename =
  let entries = get_all () in
  let json = "{\"docs\": [" ^ (String.concat ", " (List.map doc_entry_to_json entries)) ^ "]}" in
  let chan = open_out filename in      (* line 33 — unguarded *)
  output_string chan json;
  close_out chan
```
**Verdict**: `open_out` at line 33 can raise `Sys_error` if the output path is unwritable (e.g., permission denied, non-existent parent directory). This propagates uncaught to the caller. `to_json_file` is a user-facing documentation export function.
**Better fix**: Wrap in `try...with Sys_error msg -> ...` or use `Fun.protect` with a guard around `open_out` to provide a structured error message.

---

### Finding: Global mutable state (Original line: 6)
**Actual line**: 6
**Status**: CONFIRMED
**Evidence**:
```ocaml
let registry : (string, doc_entry) Hashtbl.t = Hashtbl.create 100
```
**Verdict**: Module-level mutable `Hashtbl.t` used as a global registry. Thread-safe only for single-threaded use. Since T is a single-threaded CLI tool, this is acceptable in practice but should be documented. The registry is mutated by `register`, `load_from_json`, and read by `lookup`, `get_all`, `to_json_file`.
**Better fix**: Document the thread-safety restriction. Alternatively, parameterize functions to accept and return the registry explicitly (`registry -> 'a -> 'a`) to eliminate the global.

---

### Finding: Catch-all exception handler (Original lines: 79-82)
**Actual line**: 79-82
**Status**: CONFIRMED
**Evidence**:
```ocaml
with
| Sys_error msg -> Printf.eprintf "Warning: Could not load documentation: %s\n" msg
| Tdoc_json.Json_error msg -> Printf.eprintf "Warning: Failed to parse documentation: %s\n" msg
| exn -> Printf.eprintf "Warning: Unknown error loading documentation: %s\n" (Printexc.to_string exn)
```
**Verdict**: The `| exn ->` catch-all at line 82 catches all remaining exceptions, including `Out_of_memory`, `Stack_overflow`, and any programming errors. Instead of crashing or propagating, they are downgraded to a stderr warning and silently swallowed.
**Better fix**: Re-raise `Out_of_memory` and `Stack_overflow` before the catch-all. Consider catching `Invalid_argument` from `in_channel_length` specifically.

---

## File: src/package_manager/package_loader.ml
### Finding: Catch-all `with _ -> []` silently swallows exceptions (Original line: 76)
**Actual line**: 76
**Status**: CONFIRMED
**Evidence**:
```ocaml
let load_private_names (pkg_dir : string) : string list =
  let docs_path = Filename.concat pkg_dir "help/docs.json" in
  if Sys.file_exists docs_path then begin
    try
      Tdoc_registry.load_from_json docs_path;
      let all_docs = Tdoc_registry.get_all () in
      let privates = List.filter_map (fun (entry : Tdoc_types.doc_entry) ->
        if not entry.is_export then Some entry.name else None
      ) all_docs in
      privates
    with _ -> []          (* line 76 — swallows all exceptions *)
  end else
    []
```
**Verdict**: `with _ -> []` catches ALL exceptions from `load_from_json` and `get_all`, returning an empty list. While `load_from_json` itself has a catch-all (writes to stderr), if any other exception occurs (e.g., corrupt shared memory, type error in `doc_entry` deserialization, `Out_of_memory`), it's silently treated as "no private names." This masks real bugs as missing features.
**Better fix**: Match `Sys_error` and `Tdoc_json.Json_error` explicitly. Re-raise `Out_of_memory`/`Stack_overflow`. Log unexpected exceptions at debug level.

---

## File: src/package_manager/release_manager.ml
### Finding: Catch-all exception handler in `run_command` (Original line: 65)
**Actual line**: 65
**Status**: CONFIRMED
**Evidence**:
```ocaml
let run_command cmd : (string, string) result =
  try
    let (ch_in, ch_out, ch_err) = Unix.open_process_full cmd (Unix.environment ()) in
    close_out ch_out;
    ...
    Unix.close_process_full (ch_in, ch_out, ch_err)
  with e -> Error (Printexc.to_string e)    (* line 65 — catch-all *)
```
**Verdict**: The catch-all converts every exception (including `Out_of_memory`, `Match_failure`, `Invalid_argument`) into an `Error` string. Additionally, when an exception is raised inside the `drain` loop or `Unix.select` call, the subprocess handles (`ch_in`, `ch_out`, `ch_err`) are never closed, causing a process leak (see batch 7 finding).
**Better fix**: Use `Fun.protect` to guarantee handle cleanup; catch specific exceptions (`Unix.Unix_error`, `Sys_error`); re-raise fatal ones.

---

### Finding: Catch-all exception handler in `run_command_argv` (Original line: 123)
**Actual line**: 123
**Status**: CONFIRMED
**Evidence**:
```ocaml
let run_command_argv (argv : string array) : (string, string) result =
  ...
  with e -> Error (Printexc.to_string e)    (* line 123 — catch-all *)
```
**Verdict**: Same pattern and concerns as `run_command` above. Process leak + catch-all.
**Better fix**: Same as `run_command`.

---

## File: src/package_manager/renv_resolver.ml
### Finding: Catch-all exception handler (Original line: 28)
**Actual line**: 27-28
**Status**: CONFIRMED
**Evidence**:
```ocaml
try
  let ch = open_in path in
  let content =
    Fun.protect
      ~finally:(fun () -> close_in_noerr ch)
      (fun () -> really_input_string ch (in_channel_length ch))
  in
  try
    Ok (Yojson.Safe.from_string content)
  with Yojson.Json_error msg ->
    Error (Printf.sprintf "Failed to parse renv.lock: %s" msg)
with exn ->
  Error (Printf.sprintf "Failed to read renv.lock: %s" (Printexc.to_string exn))
```
**Verdict**: Good: uses `Fun.protect` for `close_in_noerr` and has separate handling for JSON parse errors. But the outer `with exn ->` at line 27 catches all I/O exceptions including fatal ones (`Out_of_memory`, `Stack_overflow`). The `open_in` call itself is inside the outer `try`, so a file-not-found `Sys_error` is properly caught and converted to an error string, which is correct behavior.
**Better fix**: The `open_in` path is correctly handled. However, add `| Out_of_memory | Stack_overflow as exn -> raise exn` before the catch-all to let fatal exceptions propagate.

---

## File: src/package_manager/test_discovery.ml
### Finding: Catch-all silently swallows all exceptions in `run_test_file` (Original lines: 98-99)
**Actual line**: 98-99
**Status**: CONFIRMED
**Evidence**:
```ocaml
try
  let program = Parser.program Lexer.token lexbuf in
  let rec eval_imports env = function
    | [] -> env
    | stmt :: rest ->
        let (_, new_env) = Eval.eval_statement env stmt in
        eval_imports new_env rest
  in
  eval_imports env program
with
| Out_of_memory | Stack_overflow as exn -> raise exn   (* line 98 — re-raise fatals *)
| _ -> env (* Ignore errors in src for now, or maybe report? *)  (* line 99 *)
```
**Verdict**: The review correctly notes that `Out_of_memory` and `Stack_overflow` are re-raised (good). But all other exceptions — including parse errors, evaluation errors, type errors in source files — are silently swallowed and the environment is returned unchanged. The comment acknowledges this: "Ignore errors in src for now, or maybe report?". This means a broken source file will be silently ignored during test runs, potentially causing confusing test failures.
**Better fix**: At minimum, log suppressed errors. Better: propagate them as test failures rather than silently continuing.

---

### Finding: Catch-all exception handler in `run_test_file` outer try (Original lines: 147-151)
**Actual line**: 147-151
**Status**: CONFIRMED
**Evidence**:
```ocaml
| Lexer.SyntaxError msg -> ...
| Parser.Error -> ...
| Sys_error msg -> ...
| exn ->
    let duration = Unix.gettimeofday () -. start in
    { file; success = false;
      error_msg = Some (Printf.sprintf "Unexpected: %s" (Printexc.to_string exn));
      duration }
```
**Verdict**: The outer `try` block catches specific exceptions for lexer/parser/sys errors (lines 132-146), but the `| exn ->` at line 147 is a catch-all. Note that `Out_of_memory` and `Stack_overflow` raised from the inner `try` (line 98) will reach this catch-all and be converted to a test failure instead of crashing. This is debatably acceptable as test-framework behavior, but converting fatal exceptions to test failures loses diagnostic information.
**Better fix**: Add `| Out_of_memory | Stack_overflow as exn -> raise exn` before the catch-all.

---

## Math files (all 26 files) — Skipped Verification
All 26 files in `src/packages/math/` had **zero findings** in the review. Files:
`acos.ml`, `acosh.ml`, `asin.ml`, `asinh.ml`, `atan.ml`, `atan2.ml`, `atanh.ml`, `ceiling.ml`, `cos.ml`, `cosh.ml`, `floor.ml`, `math_common.ml`, `pow.ml`, `round.ml`, `sign.ml`, `signif.ml`, `sin.ml`, `sinh.ml`, `t_abs.ml`, `tan.ml`, `tanh.ml`, `t_exp.ml`, `t_iota.ml`, `t_log.ml`, `t_sqrt.ml`, `trunc.ml`

## Other files with "No issues found" — Skipped Verification
- `tdoc_types.ml`, `tdoc_json.ml`, `tdoc_markdown.ml`
- `documentation_manager.ml`, `package_types.ml`, `template_engine.ml`

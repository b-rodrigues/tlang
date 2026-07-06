# Verification Report: batch 7 (package_manager)

## File: src/package_manager/package_loader.ml
### Finding: IO leak — unguarded file handle (Original lines: 121-123)
**Actual line**: 121-123
**Status**: CONFIRMED
**Evidence**:
```ocaml
let (pkg_env, defined_names) = List.fold_left (fun (env, names) file ->
  let ch = open_in file in                                    (* line 121 *)
  let content = really_input_string ch (in_channel_length ch) in  (* line 122 *)
  close_in ch;                                                (* line 123 *)
  let lexbuf = Lexing.from_string content in
  ...
) (base_env, []) files in
...
with
| Lexer.SyntaxError msg -> ...
| Parser.Error -> ...
| Sys_error msg -> ...
```
**Verdict**: `open_in` at line 121 is immediately followed by `really_input_string` and `close_in` at line 123. If `really_input_string` or `in_channel_length` raises any exception (e.g., `Sys_error`, `Out_of_memory`), `close_in` at line 123 is skipped, leaking the file handle. The outer exception handlers at lines 134-139 catch `Lexer.SyntaxError`, `Parser.Error`, and `Sys_error`, but not `End_of_file` (from oversized file during `really_input_string`) or `Out_of_memory`. Additionally, the `Sys_error` handler at line 138 only catches `Sys_error` from the entire fold block — it doesn't close the specific leaking handle.
**Better fix**:
```ocaml
let ch = open_in file in
let content = Fun.protect ~finally:(fun () -> close_in_noerr ch)
    (fun () -> really_input_string ch (in_channel_length ch))
in
```

---

### Finding: Catch-all `with _ -> []` (Original line: 76)
**Actual line**: 76
**Status**: CONFIRMED
**Evidence**:
```ocaml
with _ -> []    (* line 76 — swallows all exceptions *)
```
**Verdict**: Same finding as batch 5 WARNING. Catches every exception from `Tdoc_registry.load_from_json` / `get_all` and returns an empty list of private names. This can mask real errors as "no private names" behavior.
**Better fix**: Match `Sys_error` and `Tdoc_json.Json_error` specifically; re-raise `Out_of_memory`/`Stack_overflow`.

---

## File: src/package_manager/release_manager.ml
### Finding: Process leak in `run_command` (Original lines: 9-65)
**Actual line**: 9-65
**Status**: CONFIRMED
**Evidence**:
```ocaml
let run_command cmd : (string, string) result =
  try
    let (ch_in, ch_out, ch_err) = Unix.open_process_full cmd (Unix.environment ()) in
    close_out ch_out;
    ...
    let rec drain out_open err_open = ...
    drain true true;
    let status = Unix.close_process_full (ch_in, ch_out, ch_err) in
    ...
  with e -> Error (Printexc.to_string e)    (* catch-all, no cleanup *)
```
**Verdict**: If the `drain` function or `Unix.select` raises any exception, execution jumps to `with e ->` at line 65 without calling `Unix.close_process_full`. The subprocess handles (`ch_in`, `ch_out`, `ch_err`) are never closed, leaking the child process (zombie). The catch-all doesn't close the handles either. Also confirms the batch 5 catch-all finding.
**Better fix**: Use `Fun.protect` with proper cleanup:
```ocaml
let (ch_in, ch_out, ch_err) = Unix.open_process_full cmd ... in
Fun.protect ~finally:(fun () ->
  close_out_noerr ch_out;
  close_in_noerr ch_in;
  close_in_noerr ch_err
) (fun () -> ... drain ... Unix.close_process_full ...)
```

---

### Finding: Process leak in `run_command_argv` (Original lines: 69-123)
**Actual line**: 69-123
**Status**: CONFIRMED
**Evidence**:
```ocaml
let run_command_argv (argv : string array) : (string, string) result =
  ...
  with e -> Error (Printexc.to_string e)    (* catch-all, no cleanup *)
```
**Verdict**: Identical structure to `run_command`. Same process leak risk from the `drain` loop.
**Better fix**: Same `Fun.protect` pattern as `run_command`.

---

### Finding: Catch-all exception handler (Original line: 65)
**Actual line**: 65
**Status**: CONFIRMED
**Evidence**: Same as above (`with e -> Error (Printexc.to_string e)`).
**Verdict**: Same as batch 5 WARNING. All exceptions (including programming errors) converted to `Error` strings.
**Better fix**: Match `Unix.Unix_error` and `Sys_error` specifically; re-raise fatal exceptions.

---

### Finding: Catch-all exception handler (Original line: 123)
**Actual line**: 123
**Status**: CONFIRMED
**Evidence**: Same pattern as line 65 in `run_command_argv`.
**Verdict**: Same as above.
**Better fix**: Same as above.

---

## File: src/package_manager/renv_resolver.ml
### Finding: Function length — `split_packages` exceeds 80 lines (Original lines: 90-179)
**Actual line**: 90-179 (89 lines)
**Status**: CONFIRMED
**Evidence**:
```ocaml
let split_packages ~project_root : (string list * r_git_dependency list, string) result =
  match read_renv_lock ~project_root with
  | Error msg -> Error msg
  | Ok json ->
    let (_r_version, parsed_packages) = parse_renv_lock_json json in
    let cran_pkgs = ref [] in
    let git_pkgs = ref [] in
    let unsupported = ref [] in
    List.iter (fun (name, source, ...) -> ...) parsed_packages; (* lines 100-135 *)
    ...
    let resolve_remotes ... = ... in                          (* lines 139-170 *)
    let git_deps = List.map resolve_remotes git_pkgs_list in
    ...
    Ok (List.rev !cran_pkgs, git_deps)
```
**Verdict**: 89 lines, exceeding the 80-line guideline. The function handles package classification (CRAN vs Git vs unsupported), remote URL construction, and recursive remotes resolution — three distinct concerns. The inline `resolve_remotes` closure at lines 139-170 is itself 31 lines.
**Better fix**: Extract `resolve_remotes` to a separate top-level function. Extract the `List.iter` classification logic into a helper function. This is a style/readability recommendation, not a bug.

---

### Finding: Mutable state in `split_packages` (Original lines: 96-98)
**Actual line**: 96-98
**Status**: CONFIRMED
**Evidence**:
```ocaml
let cran_pkgs = ref [] in
let git_pkgs = ref [] in
let unsupported = ref [] in
List.iter (fun (name, source, requirements, remote_host, remote_username,
               remote_repo, remote_sha, remotes, remote_subdir) ->
  match source with
  | "Repository" | "Bioconductor" ->
      cran_pkgs := name :: !cran_pkgs
  | "GitHub" | "GitLab" as src ->
      ...
      git_pkgs := (name, url, sha, ...) :: !git_pkgs
  | _ ->
      unsupported := name :: !unsupported
) parsed_packages;
```
**Verdict**: Three `ref` cells mutated via `List.iter` with a 10-element tuple destructure. The mutable approach works but a functional `List.fold_left` returning a triple of `(cran list, git list, unsupported list)` would be more idiomatic and eliminate all mutable state.
**Better fix**: Replace with `List.fold_left` accumulating a `(string list, r_git_info list, string list)` triple.

---

### Finding: Style — `List.assoc` instead of `List.assoc_opt` (Original line: 33)
**Actual line**: 33
**Status**: CONFIRMED
**Evidence**:
```ocaml
let get_string member json =
  match json with
  | `Assoc pairs ->
    (try Some (List.assoc member pairs) with Not_found -> None)   (* line 33 *)
  | _ -> None
```
**Verdict**: Uses `try...with Not_found` where `List.assoc_opt member pairs` would be cleaner and avoid exception-based control flow. Not a bug, purely a style recommendation.
**Better fix**: Replace `try Some (List.assoc member pairs) with Not_found -> None` with `List.assoc_opt member pairs`.

---

### Finding: Missing docstrings (various lines)
**Actual line**: 8-9, 30-34, 36-39, 41-45, 47-76, 78-88, 181-184, 186-189
**Status**: CONFIRMED
**Evidence**: The following functions lack `(** ... *)` docstrings:
```ocaml
let is_base_r_package name = ...                                  (* line 8 *)
let get_string member json = ...                                  (* line 30 *)
let get_string_value member json = ...                            (* line 36 *)
let get_string_list member json = ...                             (* line 41 *)
let parse_renv_lock_json json = ...                               (* line 47 *)
let sanitize_remote_string s = ...                                (* line 78 *)
let read_and_split_cran_packages ~project_root : string list = ...   (* line 181 *)
let read_and_split_git_packages ~project_root : r_git_dependency list = ... (* line 186 *)
```
**Verdict**: Eight functions lack documentation. `read_and_split_cran_packages` and `read_and_split_git_packages` are public interface functions; the others are internal helpers but should still be documented per the codebase convention.
**Better fix**: Add `(** ... *)` docstrings to all functions, especially the public-facing `read_and_split_*` functions.

---

## File: src/package_manager/test_discovery.ml
### Finding: Function length — `run_test_file` exceeds 80 lines (Original lines: 56-151)
**Actual line**: 56-151 (95 lines)
**Status**: CONFIRMED
**Evidence**:
```ocaml
let run_test_file (file : string) : test_result =     (* line 56 *)
  let start = Unix.gettimeofday () in
  try
    let content = ...
    let env = Packages.init_env () in                   (* line 66 *)
    (* Pre-load all .t files from src/ *)
    let src_dir = ...
    let env =                                           (* line 70 *)
      if Sys.file_exists src_dir && Sys.is_directory src_dir then begin
        ...
        Array.fold_left (fun env entry ->
          if Filename.check_suffix entry ".t" then begin
            ...
            try                                                    (* line 80 *)
              let src_content = ...
              try                                                  (* line 88 *)
                let program = Parser.program Lexer.token lexbuf ...
                ...
              with                                                (* line 97 *)
              | Out_of_memory | Stack_overflow as exn -> raise exn  (* line 98 *)
              | _ -> env                                          (* line 99 *)
            with Sys_error _ -> env                               (* line 100 *)
          end else env
        ) env entries                                             (* line 101-102 *)
      end else env                                                (* line 103 *)
    in
    (* Evaluate test statements *)
    let lexbuf = Lexing.from_string content in
    let program = Parser.program Lexer.token lexbuf in
    ...
    let (errors, _) = run_stmts env [] program in                 (* line 123 *)
    ...
  with                                                           (* line 131 *)
  | Lexer.SyntaxError msg -> ...                                 (* line 132 *)
  | Parser.Error -> ...                                          (* line 137 *)
  | Sys_error msg -> ...                                         (* line 142 *)
  | exn -> ...                                                   (* line 147 *)
```
**Verdict**: 95 lines. The function handles file reading, environment setup, package source pre-loading, statement evaluation, and error aggregation in a single function. The source-preloading logic (lines 70-103, 33 lines) and the test-evaluation logic (lines 106-123) are distinct concerns.
**Better fix**: Extract source-preloading into a separate `preload_package_sources` helper. Extract the statement-runner loop into a separate `eval_test_script` helper.

---

### Finding: Catch-all silently swallows exceptions (Original line: 99)
**Actual line**: 99
**Status**: CONFIRMED
**Evidence**:
```ocaml
with
| Out_of_memory | Stack_overflow as exn -> raise exn   (* line 98 — re-raises fatals *)
| _ -> env (* Ignore errors in src for now, or maybe report? *)  (* line 99 *)
```
**Verdict**: Same finding as batch 5 WARNING. All non-fatal exceptions (parse errors, evaluation errors, type errors) from loading package source files are silently swallowed, and the environment is returned unchanged. The comment acknowledges the TODO: "(or maybe report?)". A broken source file will be silently ignored during test runs.
**Better fix**: At minimum, log the suppressed error. Better: collect and report it as a test setup failure.

---

## Other files with "No issues found" — Skipped Verification
- `documentation_manager.ml`, `package_types.ml`, `template_engine.ml`

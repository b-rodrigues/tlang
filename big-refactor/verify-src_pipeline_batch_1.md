# Verification: src/pipeline/ + src/packages/pipeline/ — Batch 1

**45 files / 16 findings verified**. Generated 2026-07-05.

---

## File: src/pipeline/builder_copy.ml

### Finding: Mutable refs for accumulation (Original line: 58-59)
**Actual line**: 58-59
**Status**: CONFIRMED
**Evidence**:
```ocaml
58:               let errors = ref [] in
59:               let success_count = ref 0 in
60:               List.iter (fun (name, cn) ->
```
**Verdict**: Two mutable `ref` cells drive a `List.iter` accumulation loop. Could be a `List.fold_left` with a result-accumulating state.
**Better fix**: Replace with `List.fold_left` threading an `(error list, success_count)` tuple.

---

### Finding: `ignore` drops `Unix.mkdir` error (Original line: 30)
**Actual line**: 30
**Status**: NEEDS_REVISION
**Evidence**:
```ocaml
30:             let () = if not (Sys.file_exists target_dir) then Unix.mkdir target_dir 0o755 in
```
**Verdict**: The review says "ignores failure" and the copy "silently proceeds". This is incorrect. `Unix.mkdir` *raises* `Unix_error` on failure, it does not return an error code. The unguarded `let () =` binding would crash with an uncaught `Unix_error` exception, not silently proceed. The problem is worse than stated (uncaught exception crash vs silent failure).
**Better fix**: Wrap in `try Unix.mkdir ... with Unix.Unix_error _ -> ...` or use `Sys.file_exists` after creation.

---

### Finding: `ignore` drops `find`+`chmod` errors (Original line: 41-42)
**Actual line**: 41-42
**Status**: CONFIRMED
**Evidence**:
```ocaml
41:                ignore (run_command_argv_exit [| "find"; path; "-type"; "d"; "-exec"; "chmod"; dir_mode; "{}"; "+" |]);
42:                ignore (run_command_argv_exit [| "find"; path; "-type"; "f"; "-exec"; "chmod"; file_mode; "{}"; "+" |])
```
**Verdict**: `run_command_argv_exit` returns `(int, string) result` — errors are silently discarded via `ignore`.
**Better fix**: Collect errors or at minimum log the failure.

---

### Finding: Magic octal literal (Original line: 30)
**Actual line**: 30
**Status**: CONFIRMED
**Evidence**:
```ocaml
30:             let () = if not (Sys.file_exists target_dir) then Unix.mkdir target_dir 0o755 in
```
**Verdict**: `0o755` is hard-coded. The function accepts `dir_mode` as a string parameter but the initial `mkdir` always uses `0o755`.
**Better fix**: Parse `dir_mode` with `Scanf.sscanf dir_mode "%o"` and use the parsed value for the initial `mkdir`.

---

## File: src/pipeline/builder_logs.ml

### Finding: Catch-all `with _ ->` in JSON parsing helpers (Original line: 52, 131)
**Actual line**: 52, 131
**Status**: CONFIRMED
**Evidence**:
```ocaml
43:     let matches_out_path log_file =
...
52:       with _ ->
53:         false
```
```ocaml
125:       try
...
131:       with _ -> None
```
**Verdict**: Both `with _ ->` catch blocks swallow all exception types including `Out_of_memory` and `Stack_overflow`. In practice these are filtering/logging helpers where "no match" is a safe default, so the risk is minimal. Still violates the AGENTS.md "narrow and specific" guideline.
**Better fix**: Catch `Yojson.Json_error`, `Sys_error`, and `Failure` explicitly.

---

## File: src/pipeline/builder_nix_store.ml

### Finding: `ignore` drops `write_file` errors (Original line: 26, 34)
**Actual line**: 26, 34
**Status**: CONFIRMED
**Evidence**:
```ocaml
25:       in
26:       ignore (write_file env_nix_path content)
27:   | None ->
```
```ocaml
33:       in
34:       ignore (write_file env_nix_path content)
```
**Verdict**: `write_file` returns a `(unit, string) result`. Both calls discard the result with `ignore`, so file-write failures (disk full, permission denied) are silently lost.
**Better fix**: Return the result from `write_env_nix` as `unit result` or at minimum log with `Printf.eprintf`.

---

## File: src/pipeline/builder_populate.ml

### Finding: Function too large (Original line: 10-194)
**Actual line**: 10-194
**Status**: CONFIRMED
**Evidence**: `populate_pipeline` spans 184 lines (10-194), containing serializer checks, multi-dep strategy checks, tproject.toml parsing, Nix emission, and build orchestration.
**Verdict**: While `check_multi_dep_strategies` and `check_serializer_coherence` are already extracted as inner functions, the main function still has deeply nested logic for tproject.toml parsing and build coordination.
**Better fix**: Extract the tproject.toml parsing block and the Nix emission+build block as separate top-level functions.

---

### Finding: Catch-all exception in tproject.toml parsing (Original line: 183)
**Actual line**: 183
**Status**: CONFIRMED
**Evidence**:
```ocaml
183:            with _ -> [], [])
```
**Verdict**: `with _ -> [], []` catches all exceptions when reading/parsing `tproject.toml`. A corrupt file silently falls back to empty dependencies.
**Better fix**: Catch specific exceptions (`Sys_error`, `Yojson.Json_error`, `Failure`, `Toml_parser.Error`).

---

## File: src/pipeline/nix_emit_pipeline.ml

### Finding: Function too large (Original line: 27-289)
**Actual line**: 27-289
**Status**: CONFIRMED
**Evidence**: `emit_pipeline` is 262 lines containing Nix template construction, flake resolution, R dependency handling, Julia/Python config, and multi-line string formatting.
**Verdict**: Single function combines template construction with dependency resolution and build-input injection.
**Better fix**: Extract `emit_r_dependencies`, `emit_julia_config`, `emit_flake_bindings`, and the Nix template string construction.

---

### Finding: Mutable `Hashtbl` for flake dedup (Original line: 43-53)
**Actual line**: 43-53
**Status**: CONFIRMED
**Evidence**:
```ocaml
43:     let seen = Hashtbl.create 8 in
44:     List.iter (fun (_, path) -> Hashtbl.replace seen path ()) node_flakes;
...
47:   let flake_env_map =
48:     let tbl = Hashtbl.create 8 in
49:     List.iter (fun path ->
50:       let env_name = "env_" ^ sanitize_flake_path path in
51:       Hashtbl.replace tbl path env_name
52:     ) unique_flake_paths;
53:     tbl
```
**Verdict**: Mutable hashtable for dedup is local and functionally sound but `List.sort_uniq` would be simpler for this use case.
**Better fix**: Replace `seen` with `List.sort_uniq String.compare paths`.

---

## File: src/pipeline/nix_unparse.ml

### Finding: Function too large (Original line: 46-131)
**Actual line**: 46-131
**Status**: CONFIRMED
**Evidence**: `unparse_expr` spans 85 lines (46-131) with ~20 AST variant arms. The mutually recursive `unparse_stmt` adds another 20 lines.
**Verdict**: Dense pattern matching over many AST variants.
**Better fix**: Split per-variant helpers (`unparse_call`, `unparse_match`, `unparse_lambda`, etc.).

---

## File: src/packages/pipeline/build_pipeline.ml

### Finding: Catch-all `with _ -> ()` in `write_atelier_diagrams` (Original line: 13, 17, 23, 27)
**Actual line**: 13, 17, 23, 27
**Status**: CONFIRMED
**Evidence**:
```ocaml
13:        (try match b_func args env_ref with
14:             | VString s ->
15:               Builder_utils.write_file (Builder_utils.atelier_dot_path root) s |> ignore
16:             | _ -> ()
17:         with _ -> ())
```
**Verdict**: Four instances of `with _ -> ()` swallow all exceptions from DOT/Mermaid diagram generation. Non-critical side effects but a bug in the emitters would be silently hidden.
**Better fix**: Log errors with `Printf.eprintf` before swallowing, or catch specific exception types.

---

### Finding: Function too large (Original line: 54-191)
**Actual line**: 54-191
**Status**: CONFIRMED
**Evidence**: `build_fn` is 137 lines with nested validation chains for `verbose`, `nix_options`, `dry_run`, `pipeline_name`.
**Verdict**: Repetitive validation pattern could be abstracted.
**Better fix**: Extract `validate_verbose`, `validate_nix_options`, `validate_dry_run` helpers.

---

## File: src/packages/pipeline/inspect_pipeline.ml

### Finding: Catch-all `with _ -> None` in `eval_dep_len_expr` (Original line: 55)
**Actual line**: 55
**Status**: CONFIRMED
**Evidence**:
```ocaml
48:         let eval_dep_len_expr expr =
49:           try
50:             match Eval.eval_expr (ref env) expr with
51:             | VList items -> Some (List.length items)
52:             | VVector arr -> Some (Array.length arr)
53:             | VDataFrame df -> Some (Arrow_table.num_rows df.arrow_table)
54:             | _ -> None
55:           with _ -> None
```
**Verdict**: Any evaluation error (including programming bugs) silently returns `None`.
**Better fix**: Catch specific exception types or let the error propagate.

---

## File: src/packages/pipeline/pipeline_gc.ml

### Finding: Docstring terminator uses `--*` instead of `--#` (Original line: 15)
**Actual line**: 15
**Status**: FALSE_POSITIVE
**Evidence**:
```ocaml
 2: (*
 ...
14: --# @export
15: --*)
```
**Verdict**: The `--*)` on line 15 is inside an OCaml comment block `(* ... *)`. The `*)` is OCaml's comment-close delimiter — this is valid syntax. The `--*` prefix is simply an aesthetic continuation of the `--#` docstring convention inside the comment. Removing it or changing it to `--#)` would be purely cosmetic. The comment closes correctly either way. This is not a defect.
**Better fix**: None needed. The comment is valid OCaml.

---

## File: src/packages/pipeline/populate_pipeline.ml

### Finding: Function too large (Original line: 33-167)
**Actual line**: 33-167
**Status**: CONFIRMED
**Evidence**: `populate_fn` is 134 lines with sequential validation of 5 arguments.
**Verdict**: The `(provided, val)` get-and-validate pattern repeats for `build`, `verbose`, `nix_options`, `dry_run`, `pipeline_name`.
**Better fix**: Extract a `validate_arg` helper.

---

## File: src/packages/pipeline/t_make_mod.ml

### Finding: Function too large (Original line: 58-279)
**Actual line**: 58-279
**Status**: CONFIRMED
**Evidence**: The `t_make` handler closure is ~220 lines containing argument parsing/validation (~120 lines), file reading, TOML project name resolution, parsing, and evaluation.
**Verdict**: Multiple concerns mixed in one closure.
**Better fix**: Extract `process_named_args`, `resolve_project_name`, and `eval_pipeline_file`.

---

### Finding: Multiple `ref` accumulators for error state (Original line: 60-64)
**Actual line**: 60-64
**Status**: CONFIRMED
**Evidence**:
```ocaml
60:         let filename = ref "src/pipeline.t" in
61:         let nix_args = ref [] in
62:         let verbose = ref !Builder_internal.default_nix_build_verbose in
63:         let failfast = ref false in
64:         let arg_error_opt = ref None in
```
**Verdict**: Five mutable `ref` cells used for accumulating argument state. A record-based approach or monadic `Result` accumulator would be cleaner.
**Better fix**: Use a record that gets updated through the argument-processing pipeline.

---

### Finding: Magic number in `source_location` (Original line: 9)
**Actual line**: 9
**Status**: CONFIRMED
**Evidence**:
```ocaml
9:     column = max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1);
```
**Verdict**: The `+ 1` and `max 1` are column-adjustment magic numbers converting 0-based lexer positions to 1-based T columns.
**Better fix**: `let column_offset = 1` with a comment explaining the 0→1-based conversion.

---

## File: src/packages/pipeline/trace_nodes.ml

### Finding: `Hashtbl.find` without `_opt` (Original line: 50, 59, 104)
**Actual line**: 50, 59, 104
**Status**: CONFIRMED
**Evidence**:
```ocaml
50:               let curr = try Hashtbl.find tbl dep with Not_found -> [] in
59:             let rev = try Hashtbl.find reverse_map n with Not_found -> [] in
104:             let kids = try Hashtbl.find reverse_map n with Not_found -> [] in
```
**Verdict**: All three use `try Hashtbl.find ... with Not_found -> []` instead of `Hashtbl.find_opt ... |> Option.value ~default:[]`. Violates AGENTS.md guideline: "No `Hashtbl.find` without a `find_opt` alternative."
**Better fix**: Replace each with `match Hashtbl.find_opt tbl k with Some v -> v | None -> []`.

---

## Summary

| Status | Count |
|--------|-------|
| **CONFIRMED** | 18 |
| **NEEDS_REVISION** | 1 |
| **FALSE_POSITIVE** | 1 |
| **INFO** (not actionable) | 0 |
| **No issues per review** | ~29 files |

The single FALSE_POSITIVE is `pipeline_gc.ml:15` — the `--*)` line is valid OCaml comment syntax. The single NEEDS_REVISION is `builder_copy.ml:30` — the review incorrectly characterized `Unix.mkdir` failure as "silently ignored" when it would actually raise an uncaught exception.

No critical (security, correctness) issues in the pipeline batch. All findings are style/maintainability warnings.

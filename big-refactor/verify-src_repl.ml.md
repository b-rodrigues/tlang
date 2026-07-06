# Verification Report: src/repl.ml

---

## WARNING: `levenshtein_distance` duplicated from `src/ast.ml` (Original: lines 245-260)

### Finding: Identical implementation to `Ast.levenshtein`

**Actual lines**: 245-260
**Status**: CONFIRMED

**Evidence**:
```ocaml
245: let levenshtein_distance s t =
246:   let m = String.length s and n = String.length t in
247:   if m = 0 then n
248:   else if n = 0 then m
249:   else begin
250:     let dp = Array.make_matrix (m + 1) (n + 1) 0 in
251:     for i = 0 to m do dp.(i).(0) <- i done;
252:     for j = 0 to n do dp.(0).(j) <- j done;
253:     for i = 1 to m do
254:       for j = 1 to n do
255:         let cost = if s.[i-1] = t.[j-1] then 0 else 1 in
256:         dp.(i).(j) <- min (dp.(i-1).(j) + 1) (min (dp.(i).(j-1) + 1) (dp.(i-1).(j-1) + cost))
257:       done
258:     done;
259:     dp.(m).(n)
260:   end
```

**Verdict**: CONFIRMED. Byte-for-byte duplicate of `Ast.levenshtein` (ast.ml lines 1144-1160), differing only in variable names (`d` vs `dp`) and the extra `begin/end` wrapper. `repl.ml` already depends on `ast.ml` (uses `Ast.` prefix extensively), so the fix is trivial: replace `levenshtein_distance` usage with `Ast.levenshtein` and remove lines 245-260.

---

## WARNING: `source_location` duplicated from `src/eval.ml` (Original: lines 21-26)

### Finding: Identical implementation in repl.ml and eval.ml

**Actual lines**: 21-26
**Status**: CONFIRMED

**Evidence**:

**repl.ml** line 21:
```ocaml
let source_location ?file pos : Ast.source_location =
  {
    file;
    line = pos.Lexing.pos_lnum;
    column = max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1);
  }
```

**eval.ml** line 252:
```ocaml
let source_location ?file pos : Ast.source_location =
  {
    file;
    line = pos.Lexing.pos_lnum;
    column = max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1);
  }
```

**Verdict**: CONFIRMED. Exact byte-for-byte duplicate. Note: the function also exists at `src/packages/pipeline/t_make_mod.ml:5` (a third copy!). This function should live in a shared module (e.g., `Ast.Utils` or a new `Utils` module) and be removed from both `repl.ml` and `eval.ml`.

---

## WARNING: `handle_magic` too long with deeply nested conditionals (Original: lines 387-492)

### Finding: ~105-line magic command dispatcher

**Actual lines**: 387-492
**Status**: CONFIRMED (stylistic/architectural)

**Evidence**: The function is ~105 lines handling 10+ magic commands (`%time`, `%ls`, `%pwd`, `%cd`, `%env`, `%history`, `%objects`/`%who`, `%magic`, `%reset`, `%save`) plus an "unknown command" suggestion path. The `%cd` branch (lines 405-416) contains tilde-expansion logic with nested try/catch. The `%history` branch (lines 420-451) contains file-reading with iteration.

**Verdict**: CONFIRMED. The function is a straightforward `match` dispatch, so the complexity is mostly linear (one arm per command). However, extracting each command handler into a named function would improve readability and testability. The `%cd` and `%history` arms in particular have enough logic to justify extraction.

---

## WARNING: `cmd_repl` too long and deeply nested (Original: lines 973-1162)

### Finding: ~190-line REPL loop

**Actual lines**: 973-1162
**Status**: CONFIRMED (stylistic/architectural)

**Evidence**: The function spans ~190 lines and includes:
- Initialization (lines 974-991) — environment setup, version banner
- Symbol table setup (lines 994-996)
- Completion and hints callbacks (lines 998-1018)
- `read_input` helper (lines 1022-1028)
- Inner `repl` recursive function (lines 1030-1161):
  - Command dispatch: `:quit`/`:q` (1054-1055), `:help`/`:h` (1056-1075), `:version` (1076-1080), `:packages` (1081-1088), `:complete` (1089-1098)
  - Magic command handling (1099-1115)
  - Multi-line input reader `read_multiline` (1118-1143)

**Verdict**: CONFIRMED. The `repl` inner function at lines 1030-1161 is large and contains a `match` on the `trimmed` string value that dispatches among many commands. Extracting the command dispatcher (lines 1054-1115) into a separate function and the `read_multiline` helper (lines 1118-1143) to the module level would improve readability.

---

## WARNING: `recursive_files` uses catch-all exception handler (Original: line 835)

### Finding: `Sys.readdir` wrapped in `try ... with _ -> [||]`

**Actual line**: 835
**Status**: CONFIRMED

**Evidence**:
```ocaml
833: let recursive_files dir =
834:   let rec walk acc d =
835:     let entries = try Sys.readdir d with _ -> [||] in
836:     Array.fold_left (fun acc e ->
837:       let p = Filename.concat d e in
838:       if Sys.is_directory p then walk acc p
839:       else if Filename.check_suffix e ".ml" || Filename.check_suffix e ".t" then p :: acc
840:       else acc
841:     ) acc entries
842:   in walk [] dir
```

**Verdict**: CONFIRMED. If a directory exists but is unreadable (permission error), `Sys.readdir` raises `Sys_error`, which is silently swallowed. The function returns an empty list as if the directory had no `.ml`/`.t` files, hiding the actual error. Catching `Sys_error _` specifically and at minimum logging the issue would be better. However, this function is used only by `cmd_doc` (line 850), which is an offline documentation generation tool, so the impact is limited.

**Better fix**: `with Sys_error _ -> [||]` preserves the existing behavior for non-existent directories while making it auditable.

---

## INFO: `write_vars_csv` catch-all `with _ ->` (Original: lines 968-969)

### Finding: Silently swallows all I/O errors

**Actual lines**: 968-969
**Status**: CONFIRMED

**Evidence**:
```ocaml
900: let write_vars_csv env =
901:   match Sys.getenv_opt "ATELIER_ACTIVE" with
902:   | Some "1" ->
903:       let root = Builder_utils.get_atelier_project_root () in
904:       Builder_utils.ensure_atelier_dir root;
905:       let tmp_path = Builder_utils.atelier_vars_tmp_path root in
906:       let final_path = Builder_utils.atelier_vars_path root in
907:       begin try
908:         let oc = open_out tmp_path in
909:         Fun.protect
910:           ~finally:(fun () -> close_out_noerr oc)
911:           (fun () ->
912:             output_string oc "name,type,value\n";
...
966:           );
967:         Sys.rename tmp_path final_path
968:       with _ ->
969:         begin try Sys.remove tmp_path with _ -> () end
970:       end
971:   | _ -> ()
```

**Verdict**: CONFIRMED. The outer `try` block at line 907 catches ANY exception at line 968 with `with _ ->`. The inner catch at line 969 is a `Sys.remove` cleanup that also catches everything. This makes debugging Atelier variable CSV writing failures nearly impossible — all errors (disk full, permission denied, encoding issues, OCaml programming errors) are silently swallowed. At minimum, the error should be logged, and specific exception types should be caught:

**Better fix**:
```ocaml
with
| Sys_error msg ->
    Printf.eprintf "Warning: Failed to write Atelier variable CSV: %s\n%!" msg;
    (try Sys.remove tmp_path with Sys_error _ -> ())
| e ->
    Printf.eprintf "Warning: Failed to write Atelier variable CSV: %s\n%!" (Printexc.to_string e);
    (try Sys.remove tmp_path with Sys_error _ -> ())
```

---

## INFO: `run_file` uses `really_input_string` without size check (Original: line 69)

### Finding: Loads entire file into memory

**Actual line**: 69
**Status**: CONFIRMED (low severity)

**Evidence**:
```ocaml
66: let run_file ?failfast mode filename env =
67:   try
68:     let ch = open_in filename in
69:     let content = really_input_string ch (in_channel_length ch) in
70:     close_in ch;
71:     parse_and_eval ~filename ?failfast mode env content
```

**Verdict**: CONFIRMED — but the review itself notes this "is acceptable for a scripting language interpreter." T programs are unlikely to be gigabytes in size. This is a completely normal pattern for interpreter implementations. No fix needed.

---

## INFO: `cmd_doc` opens files without explicit encoding (Original: lines 844-862)

### Finding: Assumes system default encoding

**Actual lines**: 844-862
**Status**: CONFIRMED (low severity)

**Evidence**:
```ocaml
844: let cmd_doc args =
...
849:   if do_parse then begin
850:     List.iter (fun f -> List.iter Tdoc_registry.register (Tdoc_parser.parse_file f)) (recursive_files src_dir);
851:     let help_dir = Filename.concat dir "help" in
852:     mkdir_p help_dir;
853:     Tdoc_registry.to_json_file (Filename.concat help_dir "docs.json")
854:   end;
855:   if do_gen then begin
856:     let out_dir = Filename.concat dir "docs/reference" in
857:     mkdir_p out_dir;
858:     List.iter (fun e ->
859:       let ch = open_out (Filename.concat out_dir (e.Tdoc_types.name ^ ".md")) in
860:       output_string ch (Tdoc_markdown.generate_function_doc e); close_out ch
861:     ) (Tdoc_registry.get_all ())
862:   end
```

**Verdict**: CONFIRMED — but the review's note about Windows is largely irrelevant in the Nix-based T ecosystem. `cmd_doc` is a documentation generation tool for developers, not a user-facing feature. The encoding concern is valid only if the source files contain non-UTF-8 characters (unlikely for OCaml/T source). This is a very low-severity concern. No urgent fix needed.


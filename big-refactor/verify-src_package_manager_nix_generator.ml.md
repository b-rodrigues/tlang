# Verification: src/package_manager/nix_generator.ml

## File: src/package_manager/nix_generator.ml

### Finding: Uncaught I/O exceptions in `install_flake` break `result` contract (Original line: N/A, block: 651-671)

**Actual line**: 651-671
**Status**: CONFIRMED
**Evidence**:
```ocaml
  end else begin
    (* Backup existing flake.nix *)
    (if Sys.file_exists flake_path then begin
      let bak = flake_path ^ ".bak" in
      let ch = open_in flake_path in        (* line 655 — can raise Sys_error *)
      let old =
        Fun.protect
          ~finally:(fun () -> close_in_noerr ch)
          (fun () -> really_input_string ch (in_channel_length ch))  (* line 659 — can raise Sys_error *)
      in
      let ch_out = open_out bak in          (* line 661 — can raise Sys_error *)
      Fun.protect
        ~finally:(fun () -> close_out_noerr ch_out)
        (fun () -> output_string ch_out old)  (* line 664 — can raise Sys_error *)
    end);
    (* Write new flake.nix *)
    let ch = open_out flake_path in          (* line 667 — can raise Sys_error *)
    Fun.protect
      ~finally:(fun () -> close_out_noerr ch)
      (fun () -> output_string ch content);  (* line 670 — can raise Sys_error *)
    Ok content
  end
```
**Verdict**: The function signature is `(string, string) result` (line 624), but I/O at lines 655, 659, 661, 664, 667, and 670 can raise `Sys_error` uncaught. `Fun.protect` ensures channel close but re-raises exceptions. There is no `try/with` wrapping any of the I/O in the non-dry-run branch. The review's fix is correct: wrap the backup block and the write block each in `try ... with Sys_error e -> Error e`.

---

### Finding: Dead `Error` match arms on `git_url_to_flake_input` (Original lines: 240, 491)

**Actual line**: 240 and 491
**Status**: CONFIRMED
**Evidence**: At line 240 (`generate_project_flake`):
```ocaml
      match git_url_to_flake_input dep with
      | Ok input ->
        Printf.bprintf buf "    %s.url = \"%s\";\n"
          (nix_safe_name dep.dep_name) input
      | Error _ -> ()
```
At line 491 (`generate_package_flake`):
```ocaml
      match git_url_to_flake_input dep with
      | Ok input ->
        Printf.bprintf buf "    %s.url = \"%s\";\n"
          (nix_safe_name dep.dep_name) input
      | Error _ -> ()
```
And `git_url_to_flake_input` (lines 106-130) returns `Ok` in all code paths — never `Error`.
**Verdict**: The `| Error _ -> ()` arm is unreachable dead code. Should be removed or the match expression simplified.

---

### Finding: Hardcoded version string (Original line: 6)

**Actual line**: 6
**Status**: CONFIRMED
**Evidence**:
```ocaml
let companion_package_version = "0.1.0"
```
**Verdict**: `companion_package_version` is never referenced anywhere in this 672-line file. It is dead code and should be removed.

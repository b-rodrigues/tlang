# Verification: src/package_manager/update_manager.ml

## File: src/package_manager/update_manager.ml

### Finding: Catch-all exception handler in `run_git_ls_remote_tags` (Original line: 373)

**Actual line**: 373
**Status**: NEEDS_REVISION
**Evidence**:
```ocaml
let run_git_ls_remote_tags url =
  ...
  try
    let argv = [| "git"; "ls-remote"; "--tags"; url |] in
    let ch_in, ch_out, ch_err =
      Unix.open_process_args_full "git" argv (Unix.environment ())
    in
    close_out ch_out;
    ...
    | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> Error "git ls-remote terminated unexpectedly"
  with _ -> Error "git ls-remote invocation failed"
```
**Verdict**: The `with _ ->` at line 373 catches all unexpected exceptions (e.g., `Unix.Unix_error` from `open_process_args_full`, `Sys_error` from `Unix.descr_of_in_channel`) and maps them to a generic message. The review's proposed fix (catching only expected `Unix_error`/`Sys_error`) is too aggressive — it would let genuinely unexpected exceptions propagate. A better middle-ground is the review's alternative suggestion: include the exception in the error message using `Printexc.to_string`.

**Better fix**:
```ocaml
  with exn -> Error (Printf.sprintf "git ls-remote invocation failed: %s" (Printexc.to_string exn))
```

---

### Finding: `read_file` leaks channel on partial read failure (Original lines: 35-41)

**Actual line**: 35-41
**Status**: CONFIRMED
**Evidence**:
```ocaml
let read_file path =
  try
    let ch = open_in path in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Ok content
  with Sys_error msg -> Error msg
```
**Verdict**: If `really_input_string` (line 38) or `in_channel_length` (line 38) raises `Sys_error`, the exception is caught at line 41 but `close_in ch` at line 39 is never reached. The file descriptor leaks until GC finalization. The review's fix using `Fun.protect` is correct.

**Better fix**: Identical to review's suggestion:
```ocaml
let read_file path =
  try
    let ch = open_in path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ch)
      (fun () ->
        let content = really_input_string ch (in_channel_length ch) in
        Ok content)
  with Sys_error msg -> Error msg
```

---

### Finding: Misleading error message in `cmd_upgrade` catch-all (Original line: 902)

**Actual line**: 894-902
**Status**: CONFIRMED
**Evidence**:
```ocaml
              try                                     (* line 894 *)
                let oc = open_out tproject_path in    (* writes tproject.toml *)
                Fun.protect
                  ~finally:(fun () -> close_out_noerr oc)
                  (fun () -> output_string oc new_content);
                Printf.printf "Regenerating flake.nix and updating dependencies...\n";
                flush stdout;
                update_flake_lock ()                  (* line 901 — can fail independently *)
              with e -> Error (Printf.sprintf "Failed to update tproject.toml: %s" (Printexc.to_string e))  (* line 902 *)
```
**Verdict**: The `try` block covers both the TOML write (lines 895-898) and `update_flake_lock ()` (line 901). If the TOML write succeeds but `update_flake_lock` fails (e.g., Nix build error), the message at line 902 incorrectly says "Failed to update tproject.toml". The two operations should be in separate try/with blocks. The error from line 902 matches on `tproject.toml` but the error could actually be from `update_flake_lock`.

**Better fix**: Separating the two operations and matching messages to their origins (after confirming the TOML write) would be more correct.

Before the next release, these are the main issues I found during a static review of the repository.

1. ~~High: command injection risk in `t publish`~~
   - File: `/home/runner/work/tlang/tlang/src/package_manager/release_manager.ml`
   - ~~The publish flow builds shell command strings from package metadata such as the version in `DESCRIPTION.toml` and executes them through shell-based process APIs. If version/tag content is not strictly constrained before command construction, this can become shell injection.~~
   - **Fixed:** `create_git_tag` / `push_git_tag` now use `run_command_argv` (argv-based `Unix.open_process_args_full`, no shell interpolation). Added `validate_version_format` whitelist. `cmd_publish` now validates version format, git remote, and changelog before tagging.

2. ~~High: unsafe deserialization exposed through `deserialize()`~~
   - Files:
     - `/home/runner/work/tlang/tlang/src/serialization.ml`
     - `/home/runner/work/tlang/tlang/src/packages/base/deserialize.ml`
   - ~~The code uses `Marshal.from_channel` on file contents. OCaml Marshal is not safe for untrusted input, so loading externally supplied `.tobj` files is a security risk.~~
   - **Fixed:** `serialize_to_file` now writes a MD5 content digest; `deserialize_from_file` verifies it before unmarshalling. Legacy (digest-less) files are still accepted with a stderr warning for backward compatibility.

3. ~~Medium: release workflow looks stale / incomplete~~
   - Files:
     - `/home/runner/work/tlang/tlang/src/package_manager/release_manager.ml`
     - `/home/runner/work/tlang/tlang/src/repl.ml`
   - ~~`validate_changelog` exists but is not used by `cmd_publish`.~~
   - ~~`validate_git_remote` also exists but is not used in `cmd_publish`.~~
   - The publish path runs `dune test` directly instead of the repository's documented Nix-based workflow.
   - **Partially fixed:** `cmd_publish` now calls `validate_version_format`, `validate_clean_git`, `validate_git_remote`, and `validate_changelog` (as a warning). The `dune test` vs Nix-workflow discrepancy remains.

---

### Additional issues (most serious → least serious)

4. ~~Medium-High: shell injection in pipeline builder via user-controlled paths~~
   - Files:
     - `src/pipeline/builder_internal.ml` (lines 40, 69-70)
     - `src/pipeline/builder_copy.ml` (lines 33-42, 68)
     - `src/pipeline/builder_inspect.ml` (line 58)
     - `src/pipeline/builder_utils.ml` (line 26)
   - ~~`nix-build`, `nix log`, `cp`, and `rm -rf` commands are constructed via `Printf.sprintf` with `Filename.quote` and executed through `Sys.command` / `open_process_full`. While `Filename.quote` mitigates basic injection, it is not robust on all platforms (especially Windows). These should be converted to argv-based execution (`Unix.open_process_args_full`) like the publish flow was.~~
   - **Fixed:** Added `run_command_stream_argv`, `run_command_argv_exit`, and `run_command_argv_capture` to `builder_utils.ml`. Converted `nix-build`, `nix log`, `cp -RP`, `rm -rf`, and `find … -exec chmod` calls in `builder_internal.ml`, `builder_copy.ml`, and `builder_inspect.ml` to argv-based execution.

5. ~~Medium: `curl` invocation in `arrow_io.ml` lacks safety flags~~
   - File: `src/arrow/arrow_io.ml` (line 206)
   - ~~URL downloads shell out to `curl -s -L` without `--fail`, `--max-time`, or `--max-filesize`. HTTP errors (4xx/5xx) are silently treated as success and the error page is written to the temp file. No timeout means a hung server can block the process indefinitely.~~
   - **Fixed:** Added `--fail` (reject HTTP errors), `--max-time 120` (2-minute timeout), and `--max-filesize 536870912` (512 MB limit).

6. Medium: `shell()` in eval.ml executes arbitrary user strings via shell
   - File: `src/eval.ml` (lines 460-500)
   - **Description:** The `shell()` builtin (evaluating `ShellExpr` AST nodes) passes user-provided strings verbatim to `Unix.open_process_full cmd (Unix.environment ())`, which invokes `/bin/sh -c <cmd>`. The environment is fully inherited (all env vars, full PATH). This is intentional — `shell()` is a power-user escape hatch — but it is currently completely ungated.

   **Risk surface:**
   - Any T script that calls `shell()` can execute arbitrary host commands, exfiltrate files, or modify system state.
   - In multi-user or pipeline-runner contexts (e.g. a shared CI node running untrusted `.t` scripts), this is equivalent to unrestricted code execution.
   - There is no audit log, no deny-list, and no way for an operator to disable the builtin without patching the binary.

   **Design options (not yet implemented — needs a decision):**

   1. **Environment-variable opt-in (recommended minimum).** `shell()` checks for `TLANG_ALLOW_SHELL=1` at call time. If the variable is absent or set to `0`, `shell()` returns a `VError` with a message explaining how to enable it. This requires zero code change to existing scripts that run in environments where the operator sets the variable; scripts that forget the variable get a clear diagnostic instead of silent injection.

      ```ocaml
      (* In eval_shell_expr, before the Unix.open_process_full call: *)
      (match Sys.getenv_opt "TLANG_ALLOW_SHELL" with
       | Some "1" -> (* proceed *)
       | _ -> Error.make_error ShellError
           "shell() is disabled. Set TLANG_ALLOW_SHELL=1 to enable arbitrary shell execution.")
      ```

   2. **CLI flag `--allow-shell`.** The REPL/runner sets a global flag when invoked with `t run --allow-shell myfile.t`. `eval_shell_expr` checks the flag. This gives per-invocation control and makes the capability visible in `ps` output / shell history.

   3. **`secure_mode` interpreter flag.** A broader `--secure` flag (or `TLANG_SECURE=1`) that disables `shell()`, filesystem writes from T code, and any other privileged builtins. Useful for running untrusted T scripts in a sandbox.

   **Recommendation:** Implement option 1 (env-var guard) as the minimal safe default. Add a note to the documentation for `shell()` explaining the security model regardless of which option is chosen. Option 2 can be layered on top later.

   **Files to change if implementing option 1:**
   - `src/eval.ml` — add env-var check in `eval_shell_expr` before `Unix.open_process_full`
   - `docs/` — document the `TLANG_ALLOW_SHELL` variable and its implications

7. ~~Medium-Low: `Option.get` and `failwith` in user-facing stats functions~~
   - Files:
     - `src/packages/stats/skewness.ml` (line 72)
     - `src/packages/stats/cv.ml` (line 72)
     - `src/packages/stats/winsorize.ml` (lines 77-78)
     - `src/packages/stats/mad.ml` (lines 70, 72)
   - ~~These use `Option.get` on results of `mean` / `quantile` which can return `None` on empty input. An empty vector will raise an uncaught OCaml exception instead of returning a structured `VError`. Each should pattern-match on the `None` case.~~
   - **Fixed:** Replaced all `Option.get` calls with explicit `match` expressions.

8. ~~Low: `failwith` in PMML parsing for missing attributes~~
   - File: `src/pmml_utils.ml` (lines 662, 666, 706)
   - ~~PMML XML attribute lookups use `failwith` when required attributes are missing. These should return `VError` or `Error` values rather than raising OCaml exceptions, per the project's error handling conventions.~~
   - **Fixed:** Replaced `failwith` with `raise (Invalid_argument ...)` for consistency; these are caught by the outer `try...with exn ->` handler that wraps the result in `Error`.

9. ~~Low: `List.hd` on potentially-empty list in PMML parser~~
   - File: `src/pmml_utils.ml` (line 787)
   - ~~`List.hd ints` on a list that is only conditionally non-empty. Should use pattern matching.~~
   - **Fixed:** Replaced with `match ints with p :: _ -> ... | [] -> ()` pattern match.

10. Low: `dune test` vs Nix workflow mismatch in publish
    - File: `src/package_manager/release_manager.ml` (line 161), `src/repl.ml` (line 384)
    - **Description:** `validate_tests_pass()` runs `Sys.command "dune test"` directly. The project's CI pipeline and AGENTS.md both document that tests must run under `nix develop -c dune runtest` to get the pinned toolchain, correct C library paths (Arrow, ONNX), and the full Nix environment. Running bare `dune test` at publish time:
      1. Uses whatever `dune` and OCaml are on `$PATH`, which may differ from the Nix-pinned versions.
      2. Will fail on a developer machine that has no bare `dune` installed (only the Nix-wrapped one).
      3. May silently pass if the test binary links against different shared libraries than the ones tested in CI.

   **Design options (not yet implemented — needs a decision):**

   1. **Check for Nix environment and branch.** Detect whether we are already inside a Nix shell by checking `$IN_NIX_SHELL`. If yes, run `dune runtest`. If no, prefix with `nix develop --accept-flake-config -c`:

      ```ocaml
      let cmd =
        match Sys.getenv_opt "IN_NIX_SHELL" with
        | Some _ -> "dune runtest"
        | None   -> "nix develop --accept-flake-config -c dune runtest"
      in
      match Sys.command cmd with ...
      ```

      This correctly handles both the "developer is already in `nix develop`" case and the "developer ran `t publish` from outside the shell" case.

   2. **Always use the Nix invocation.** Simply replace `"dune test"` with `"nix develop --accept-flake-config -c dune runtest"`. This is always correct but is slower (Nix environment setup overhead) and requires `nix` to be on `$PATH`.

   3. **Make test command configurable.** Read a `TLANG_TEST_CMD` environment variable, defaulting to the Nix invocation. This lets packagers or CI override the command without patching the binary:

      ```ocaml
      let cmd = Sys.getenv_opt "TLANG_TEST_CMD"
                |> Option.value ~default:"nix develop --accept-flake-config -c dune runtest"
      in
      ```

   **Recommendation:** Option 1 is the most ergonomic. Option 3 is the most portable. Both are small, safe changes. The current `"dune test"` string should not ship as-is since it gives false confidence at publish time on the typical Nix-based developer workstation where bare `dune` is unavailable.

   **Files to change:**
   - `src/package_manager/release_manager.ml` — update `validate_tests_pass`

---

Release recommendation:

- ~~Must fix before release:~~
  - ~~command injection in publish flow~~ ✅
  - ~~unsafe Marshal-based deserialization for untrusted inputs~~ ✅

- Strongly recommended before release:
  - ~~tighten publish validation flow~~ ✅ (partially — Nix-workflow mismatch remains)
  - ~~harden remote download handling (item 5)~~ ✅
  - ~~convert pipeline builder shell calls to argv-based execution (item 4)~~ ✅

- Cleanup / robustness:
  - ~~remove remaining partial-function and raw exception patterns from user-facing paths (items 7-9)~~ ✅
  - document or gate `shell()` security model (item 6) — see design options above; env-var guard recommended
  - fix `dune test` vs Nix workflow mismatch in publish (item 10) — see design options above; option 1 or 3 recommended

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
   - File: `src/eval.ml` (line 477)
   - The `shell()` builtin passes user-provided strings directly to `Unix.open_process_full`, which invokes `/bin/sh -c`. This is by design (it's a shell command), but there is no sandboxing, no PATH restriction, and no opt-in security gate. Consider at minimum documenting the risk and potentially adding a `--allow-shell` flag or environment variable guard.

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
    - File: `src/package_manager/release_manager.ml`
    - `validate_tests_pass` runs `dune test` directly, but the project's CI and documented workflow uses `nix develop -c dune runtest`. This means publish-time test validation may use a different toolchain/environment than CI.

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
  - document or gate `shell()` security model (item 6)

Before the next release, these are the main issues I found during a static review of the repository.

1. High: command injection risk in `t publish`
   - File: `/home/runner/work/tlang/tlang/src/package_manager/release_manager.ml`
   - The publish flow builds shell command strings from package metadata such as the version in `DESCRIPTION.toml` and executes them through shell-based process APIs. If version/tag content is not strictly constrained before command construction, this can become shell injection.

2. High: unsafe deserialization exposed through `deserialize()`
   - Files:
     - `/home/runner/work/tlang/tlang/src/serialization.ml`
     - `/home/runner/work/tlang/tlang/src/packages/base/deserialize.ml`
   - The code uses `Marshal.from_channel` on file contents. OCaml Marshal is not safe for untrusted input, so loading externally supplied `.tobj` files is a security risk.

3. Medium: release workflow looks stale / incomplete
   - Files:
     - `/home/runner/work/tlang/tlang/src/package_manager/release_manager.ml`
     - `/home/runner/work/tlang/tlang/src/repl.ml`
   - `validate_changelog` exists but is not used by `cmd_publish`.
   - `validate_git_remote` also exists but is not used in `cmd_publish`.
   - The publish path runs `dune test` directly instead of the repository's documented Nix-based workflow.

4. Medium: remote file fetching is not hardened enough
   - File: `/home/runner/work/tlang/tlang/src/arrow/arrow_io.ml`
   - URL downloads shell out to `curl -s -L` without timeout, size limits, or `--fail`. This can mask HTTP failures and leaves the release exposed to brittle or abusable network behavior.

5. Low: partial functions / exception-based paths remain in user-facing code
   - Files include:
     - `/home/runner/work/tlang/tlang/src/pmml_utils.ml`
     - `/home/runner/work/tlang/tlang/src/packages/stats/skewness.ml`
     - `/home/runner/work/tlang/tlang/src/packages/stats/cv.ml`
     - `/home/runner/work/tlang/tlang/src/packages/stats/winsorize.ml`
     - `/home/runner/work/tlang/tlang/src/packages/stats/mad.ml`
   - There are still `failwith`, `Option.get`, and similar partial-function patterns in areas that should ideally return structured `VError` values instead of relying on exceptions.

Release recommendation:

- Must fix before release:
  - command injection in publish flow
  - unsafe Marshal-based deserialization for untrusted inputs

- Strongly recommended before release:
  - tighten publish validation flow
  - harden remote download handling

- Cleanup / robustness:
  - remove remaining partial-function and raw exception patterns from user-facing paths

# Path to 0.55.5: Design Gaps Found Reading the Book and the Docs

Source: full read of `../reproducible-data-science` (16 chapters + plan)
against `tlang` 0.55.4, plus defects found while fixing the
`model_capabilities_demo_t` CI timeout. Each item below states the problem,
the evidence, a proposed direction, and acceptance criteria. None of these
changes existing syntax on its own; anything that does needs maintainer
approval per AGENTS.md first.

Status convention: `- [ ]` open, `- [x]` done.

---

## 1. Silent capture across the sandbox boundary

**Problem.** Node code looks like a closure but runs in a fresh environment.
Outer values are inlined silently at construction, so users cannot tell what
crosses the boundary.

**Evidence.** Three defects from one cause, all found in the 0.55.4 cycle:
- Stale reads after shadowing (`x = 1` in a block kept resolving outward).
- The reassignment trap (`x := y + 1` on a captured outer inlined the stale
  value or dangled).
- The `default(...)` emitter fallback (raw-string strategy produced calls
  that spun forever; see item 2).

**Direction.** Make capture visible instead of silent. Options, cheapest
first:
- [x] Document the exact capture rule in one place (done: `node` docstring
  in `node_docs.ml` + mirrored `docs/reference/node.md`): frozen data,
  local shadowing, symbolic functions/builtins, deferred quoted code,
  construction error on captured-data reassignment. Verified each claim
  against the implementation and a live build before writing.
- [x] Pin the rule with unit tests (done: frozen-literal, lambda-symbolic,
  shadowing, rejection, quoted/builtin exemptions in `test_pipeline.ml`).
- [x] Cover it with a demo (done: `t_demos/capture_transparency_t` with
  passing asserts, verified end to end on a real `populate_pipeline`
  build).
- [ ] Consider a construction warning for inlining (deferred: capture is
  the normal mechanism and T values are immutable, so a warning would fire
  on all ordinary use — documentation plus tests carry this for now).

**Acceptance.**
- [x] The documented rule matches the implemented `substitute_env_vars`
  behavior on shadowing, reassignment, lambdas, builtins, and quoted code.
- [x] No new warnings fire on the existing test suite or `t_demos` (the
  check surfaces as a construction error, and the full suite is green).

---

## 2. Strategies are strings, not types

**Problem.** Serializer/deserializer strategies are bare symbols (`^csv`,
`default`). A typo or a missing table entry falls through to raw text and
breaks far from the cause — at node runtime, or never (silent wrong
behavior).

**Evidence.** `nix_emit_node.ml` fell back to the raw string `"default"`,
emitting `= default(...)` calls for every default-serializer node. No
`default` builtin exists; calling the bare symbol looped `eval_call`
forever at 100% CPU. Fixed in 0.55.4 by mapping `"default"` explicitly and
by failing fast on symbol-to-symbol calls — but the next missing entry
fails the same silent way.

**Direction.**
- [x] Centralize the strategy tables so readers and writers share one
  mapping per runtime (done: single `io_fns` table with `lookup_writer` /
  `lookup_reader` in `nix_emit_node.ml`; the separate `read_fns` /
  `write_fns` lists are gone). Bonus fix found while merging: `^text` had
  a writer but no reader, so it emitted the same bare-call hang —
  it now reads via `read_file`, with a test.
- [x] Unknown strategies are a construction-time error naming the valid
  set — verified already covered (`^arrow → ^ipc` hint path); the emitter
  fallback can no longer produce bare calls.
- [x] Closed strategy type, no grandfathering (done): only built-ins
  (`default`, `^csv`, …) and strategy dicts (`[format: ^name, ...snippets]`,
  closed keys, `format` required, custom formats carrying an inline
  snippet for the node's runtime and role) are strategies. Bare names
  fail at node() construction naming the valid set and the dict form;
  validation rejects unknown keys, missing `format`, non-code snippets,
  and snippet-less custom formats; the emitter can no longer produce
  bare calls. Demos, tests, and doc examples use dicts only — the
  `custom("name")` quoting escape was removed entirely, no legacy.
- [ ] Long term: removed in favor of strategy dicts — custom formats are
  `[format: ^name, ...snippets]` dicts (closed keys, validated per
  runtime/role), so typos fail at `t check` with the dict form named.
  No quoting escape remains.

**Acceptance.**
- [x] No emitter path can produce a bare `name(...)` call for a strategy:
  per-runtime `not (has "= default(")` assertions (T/R/Python/Julia),
  loud `Invalid_argument` naming the valid set for known-but-unmapped
  formats (^bin outside fetchurl), passthrough preserved for custom
  function names.
- [x] `t check` tier 1 reports unknown strategies with the valid set
  (same `collect_errors` path as `pipeline_validate`; existing ^arrow
  tests).

---

## 3. Dependency inference is lexical, not scoped

**Problem.** T scans command text for names matching sibling nodes, with a
growing list of exceptions (comments, string literals, `read_node("name")`
kept deliberately). Each new syntax feature needs another carve-out, and a
missed one silently rewires the DAG.

**Direction.**
- [x] Scope-aware analysis (done): `Ast.extract_local_bindings ~runtime`
  collects block-level bindings per runtime idiom (R `<-`/`=`/`->`/for
  with function-body skipping; Python `=`/`:=`/`for`/`def` with
  indent-tracked suite skipping; Julia `=`/named definitions with an
  end-matched scope stack, loop vars excluded; sh statement-start `=` and
  `for`, `local` excluded). `compute_deps` subtracts them before sibling
  matching while always keeping `read_node("name")` literals. Certain-only:
  ambiguous forms (kwargs, comparisons, tuple unpacking, imports, nested
  suites, class bodies) keep the edge — a spurious edge fails loudly at
  cycle check, a dropped real edge would silently under-build.
- [x] Dedicated regression tests per rule plus no-false-negative tests
  (kwarg keeps edge, `==`/`< -` keep working, `f(x = 1)` keeps edge) in
  `test_pipeline_comments.ml`, alongside pipeline-level `p_deps` tests
  (shadow drops edge, kwarg keeps edge, read_node preserved).
- [x] Follow-up (done): `pipeline_expand.ml` now consults block locals
  (done: `Ast.dep_substitution_spans` limits raw-text replacement to
  pre-binding reads plus the binding RHS; binders and later local reads
  stay bare; unbound names keep legacy whole-text replacement).

**Acceptance.**
- [x] `phantom_deps_t` and its siblings still pass; each exception has a
  dedicated test naming the rule.
- [x] No behavior change on the existing suite (inference results identical
  except for fixed cases; full suite green).

---

## 4. The shell is all or nothing

**Problem.** Every generated project shell materializes R, Python, and
Julia, even for pure-T projects. Cold devShell builds dominate demo CI
times (60–90+ minutes observed for tiny pipelines), and most of it is
downloading and precompiling runtimes the demo never touches.

**Direction.**
- [x] Slim shells (done, measured): a pure-T generated shell went from 10
  locally-built derivations (Julia depot precompile, Python env, R wrapper)
  to 1 (the shell itself) via `nix build --dry-run`. Rule: full runtime
  envs only when the project declares that runtime (`r_deps`/`r_git_deps`
  with renv already merged in, `py_deps` or uv resolver, user `jl_deps`
  before the forced JSON). Bare interpreters stay for ad-hoc use and
  editor discovery; node builds always used `pipeline.nix` envs and are
  unaffected. Declaring any dependency restores the full env on `t update`.
  Unit tests pin both shapes; real flake regenerates, parses, and dry-runs
  clean.

**Acceptance.**
- [ ] A pure-T scaffolded project enters its shell measurably faster than
  today; a polyglot project is unchanged.
- [ ] `t_demos` pure-T workflows get faster without workflow edits.

---

## 5. Prompts inside builds

**Problem.** The missing-dependency prompt can read from `stdin` during a
build (`pipeline_dependency_requirements.ml`). Non-interactive runs should
never ask; on EOF it currently declines, but any open-stdin context blocks
instead of failing fast.

**Direction.**
- [x] Gate every prompt path so non-terminal stdin never blocks (done:
  `read_prompt_answer` returns `None` immediately when not a tty instead
  of reading stdin, where a held-open pipe would wait forever; verified
  with stdin held open — fast actionable error, no wait).
- [x] Unattended opt-out (done: `TLANG_NO_PROMPT=1` makes
  `prompt_to_update` decline before any tty check or stdin read; unit
  tested with save/restore). Note: `ensure_project_requirements` already
  gated on `is_interactive` before reaching the prompt; the fix covers
  direct callers and terminal-attached suites.
- [x] Per-command flags (done: `t run --yes <file.t>` answers yes and
  `t run --no <file.t>` declines, on `run`/`repl`/`test`/`explain`;
  both together is a CLI error). `--no` joins the decline path, so it
  wins over `--yes` and every env var, and it also blocks the
  `TLANG_AUTO_ADD_PIPELINE_DEPS=1` absent-file bypass; `--yes` joins the
  affirm path but never grants that bypass (absent `tproject.toml` still
  errors). Unit tested per source and per combination, plus `t check`-free
  held-open-stdin runs that return immediately.
- [x] Per-command `--yes`/`--no` CLI flags (done, see above; env vars
  still cover scripts and CI that prefer ambient configuration).

**Acceptance.**
- [x] `t run <pipeline-with-missing-deps < /dev/null` errors immediately
  with an actionable message; never blocks.
- [x] Same command with stdin held open (no EOF) still never blocks
  (verified manually with `sleep 45 |`).

---

## 6. Types stop where errors start

**Problem.** Errors are first-class values, but the type system does not
express "DataFrame or Error". Schema checks (`t check --schema`) cover the
happy path; error paths are invisible to them. The two flagship ideas do
not meet.

**Direction.**
- [x] Implemented the bottom-type story without new syntax (done):
  `Ast.is_compatible` treats `VError` as compatible with every annotation,
  mirroring the adjacent `VNA` bottom rule. This only ever *relaxes*
  checks along error paths: error values now propagate through typed
  lambda parameters instead of being masked by a spurious `Expected Int,
  got Error` mismatch (verified before/after on the same input). No new
  type constructor was needed — schema inference already yields
  `TUnknown` for error values. Paired with documenting fallible functions
  in `--#` blocks (ongoing, per function).
- [ ] Document which functions can return `Error` in their `--#` blocks
  (ongoing, per function; `Expect_*` vocabulary preferred at boundaries).

**Acceptance.**
- [x] Story decided and implemented without new syntax (ordered; relax-only
  by construction — no previously passing check can newly fail).
- [x] Error paths reason cleanly everywhere: runtime value checks treat
  `VError` as bottom (new), and schema inference already yields
  `TUnknown` (compatible with everything) for error expressions —
  verified `t check` reports no spurious mismatch on
  `x: Int = error("boom")`. No `TError` constructor needed.

---

## Sequencing

1. Items 1 (docs + warning) and 2 (centralize tables, construction error).
   Small, high-leverage, same code neighborhood as the 0.55.4 fixes.
2. Item 5 (prompt gating). Small, CI-facing, testable without Nix builds.
3. Item 3 (scoped inference). Medium; touches DAG semantics — needs the
   full suite plus `t_demos` spot checks.
4. Item 4 (slim shells). Medium; measure first, then cut.
5. Item 6 (error-aware types). Design-first; do not code before the story
   is written and approved.

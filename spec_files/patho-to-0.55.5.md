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
- [ ] The documented rule matches the implemented `substitute_env_vars`
  behavior on shadowing, reassignment, lambdas, builtins, and quoted code.
- [ ] No new warnings fire on the existing test suite or `t_demos` (or the
  suite is updated where the warning is correct).

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
- [ ] Centralize the strategy tables so readers and writers share one
  mapping per runtime (today `read_fns`/`write_fns` are separate lists that
  can disagree, as they did).
- [ ] Make unknown strategies a construction-time error naming the valid
  set (the `^arrow → ^ipc` precedent already exists for unknown formats;
  extend it to the emitter fallback instead of `Option.value ~default:fmt`).
- [ ] Long term: a closed strategy type instead of symbols, so typos do not
  typecheck.

**Acceptance.**
- [ ] No emitter path can produce a bare `name(...)` call for a strategy;
  add/keep the `not (has "= default(")` style assertion for every runtime.
- [ ] `t check` tier 1 reports unknown strategies with the valid set.

---

## 3. Dependency inference is lexical, not scoped

**Problem.** T scans command text for names matching sibling nodes, with a
growing list of exceptions (comments, string literals, `read_node("name")`
kept deliberately). Each new syntax feature needs another carve-out, and a
missed one silently rewires the DAG.

**Direction.**
- [ ] Scope-aware analysis: resolve references against block-local bindings
  first (reuse the `walk` discipline from the shadowing fix), then siblings,
  then outer env — instead of text scanning plus exceptions.
- [ ] Keep the `read_node("name")` literal rule, but implement it as one
  explicit case in the scoped walk rather than a text-level exception.
- [ ] Add negative regression tests per rule (comment, string, quoted code,
  shadowing) so new syntax cannot regress silently.

**Acceptance.**
- [ ] `phantom_deps_t` and its siblings still pass; each exception has a
  dedicated test naming the rule.
- [ ] No behavior change on the existing suite (inference results identical
  except for fixed cases).

---

## 4. The shell is all or nothing

**Problem.** Every generated project shell materializes R, Python, and
Julia, even for pure-T projects. Cold devShell builds dominate demo CI
times (60–90+ minutes observed for tiny pipelines), and most of it is
downloading and precompiling runtimes the demo never touches.

**Direction.**
- [ ] Record per-resolver shell timings to establish the baseline.
- [ ] Slim shells: only include the runtimes the project's nodes actually
  use (derive from `tproject.toml` sections already present).
- [ ] Long term: lazy environment provisioning on first use of a runtime.

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
- [ ] Gate every prompt on an explicit interactivity check *and* a
  non-interactive default: CI gets an error naming the fix (`t add` /
  `t update`), never a read.
- [ ] Add `--yes`/`--no` (or honor `TLANG_AUTO_ADD_PIPELINE_DEPS` /
  equivalent) so scripts declare intent up front.
- [ ] Audit remaining `read_line`/`input_line` call sites for the same
  pattern (`repl.ml` REPL loop is correctly tty-gated; keep it).

**Acceptance.**
- [ ] `t run <pipeline-with-missing-deps < /dev/null` errors immediately
  with an actionable message; never blocks.
- [ ] Same command with stdin held open (no EOF) still never blocks.

---

## 6. Types stop where errors start

**Problem.** Errors are first-class values, but the type system does not
express "DataFrame or Error". Schema checks (`t check --schema`) cover the
happy path; error paths are invisible to them. The two flagship ideas do
not meet.

**Direction.**
- [ ] Decide the story first (design doc, maintainer approval): e.g. result
  types, `Error` as a bottom type compatible with everything, or explicit
  `expect_*` contracts at node boundaries.
- [ ] Only then: implement inference/propagation for the chosen story,
  starting with pipe chains (`|>` short-circuits, `?|>` forwards).
- [ ] Document which functions can return `Error` in their `--#` blocks.

**Acceptance.**
- [ ] Open question resolved in writing before any code (this item is
  syntax-adjacent by nature).
- [ ] `t check --schema` reasons about at least one error-propagating
  construct without false positives on the existing suite.

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

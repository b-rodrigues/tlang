# T Specification: Agent-Facing Verification Surface

**Status:** Draft / RFC
**Scope:** `t check`, structured diagnostics (`--json`), and pipeline-level verification strategy
**Context:** Motivated by the Scarf/Haskell post on AI-era language economics (Press, 2026). The
argument that matters for T is not "static types are dead," it's: *the cost that determines whether
an ecosystem works well with agents is the round-trip time between an agent's edit and a trustworthy
signal about that edit* — and that signal has to be structured enough for the agent to act on without
parsing English.

T already avoids Haskell's specific failure mode (no compile step for `.t` code). The equivalent
bottleneck for T is Nix derivation realization. This document proposes a verification surface that
gives agents a fast, structured, tiered signal *before* anything gets built, plus a JSON diagnostics
protocol, plus a re-framed answer to "should there be a test suite agents run automatically" —
which, per the prompt that produced this doc, the answer is: not in the form people default to.

---

## 1. `t check`

### 1.1 Goals

- Give an agent a correctness signal in the tens-of-milliseconds range, with zero Nix derivation
  realization, so it's cheap enough to run after every edit, in every forked worktree, without
  reintroducing Scarf's "cold build tax multiplied across parallel agents" problem.
- Make the signal tiered, so cost scales with how much confidence is needed, rather than being
  all-or-nothing (parse-only vs. full pipeline execution).
- Never require network access or a Nix build to produce a tier-1 or tier-2 result.

### 1.2 Non-goals

- `t check` does not execute any node body (R/Python/Julia/shell). It cannot catch a bug in the
  *logic* of a node — only in the *shape* of the pipeline around it.
- `t check` does not replace `t run`. It's a pre-flight filter that should eliminate the large class
  of errors that are structural rather than semantic, before the agent pays for a build.

### 1.3 Tiers

| Tier | Flag | What's checked | Cost | Requires Nix |
|---|---|---|---|---|
| 1 | `t check` (default) | Parse validity, AST well-formedness, DAG structure (no cycles, no dangling node refs, no unreachable nodes), known builtins/serializers, arity of calls, `node_when`/`node_fork` static conditional exhaustiveness | ~ms, in-process | No |
| 2 | `t check --schema` | Tier 1 + static shape propagation: declared/inferred column names & types flowing through the DAG (Arrow schema at each edge), lens path validity against known schemas, formula (`y ~ x`) symbol resolution against upstream schemas | ~10s of ms | No |
| 3 | `t check --env` | Tier 1+2 + flake evaluation (not realization) for every per-node override: does the referenced Nix expression evaluate, do declared R/Python packages resolve against `renv.lock`/uv2nix lockfiles, without fetching or building anything | sub-second, no network if lockfiles are hash-pinned | Eval only |

Default `t check` is tier 1. `--schema` and `--env` are additive flags, not separate commands —
this matters for agent tooling, since it means one command with escalating `--flags` rather than
three commands to remember.

### 1.4 What tier 2 buys you given T is dynamically typed

T's interpreter is correctly dynamically typed at runtime — that's the right call for an
interpreter that has to stay simple and introspectable. But *between* nodes, the Arrow schema at
each pipe boundary is usually knowable statically (it's either declared in a serializer call, or
it's the deterministic output schema of an upstream node whose own inputs are known). Tier 2 is not
a type system bolted onto T — it's schema propagation along the DAG edges, which is a much smaller
and more tractable problem, and it directly targets the one thing agents most reliably get wrong
when editing a pipeline: a column rename or type change upstream silently breaking three nodes
downstream. That failure currently only surfaces at `t run` time, after a full Nix build of every
node in between.

### 1.5 CLI surface

```
t check                    # tier 1, default
t check --schema           # tier 1 + 2
t check --env              # tier 1 + 2 + 3
t check --watch            # re-run tier 1(+2) on file save
t check --json             # structured output, any tier (see §2)
```

Exit codes: `0` clean, `1` tier-1 structural error, `2` tier-2 schema error, `3` tier-3 env
resolution error. Distinct nonzero codes let an agent branch on "is this a five-second fix or do I
need to touch the environment" without parsing output at all.

---

## 2. `--json` diagnostics protocol

### 2.1 Design goals

- One stable, versioned schema shared by `t check`, `t run`, and (later) `t test`, so an agent
  writes one parser, not three.
- Every diagnostic is locatable (file, node id, span) and classified (machine-stable `error_class`
  string), independent of the human-readable `message`, which can change wording freely without
  breaking agent tooling.
- Diagnostics carry enough of the "before/after" for the common repair classes that an agent can
  often propose a patch without re-reading the whole node.

### 2.2 Top-level shape

```json
{
  "schema_version": "1",
  "status": "error",
  "phase": "check",
  "tier": 2,
  "diagnostics": [ /* Diagnostic[] */ ]
}
```

`phase` is one of `parse | wire | schema | env | build | exec`. This is the field an agent should
branch on first — it tells you which of §1's tiers (or `t run`'s later stages) produced the
problem, which maps directly to "how expensive will it be to iterate on this."

### 2.3 Diagnostic object

```json
{
  "id": "T0142",
  "error_class": "schema_mismatch",
  "severity": "error",
  "phase": "schema",
  "node": {
    "id": "clean_loans",
    "lang": "r",
    "file": "pipeline.t",
    "span": { "start": [14, 3], "end": [14, 27] }
  },
  "message": "column 'loan_amount' expected type <double>, node 'clean_loans' declares <string>",
  "expected": { "kind": "arrow_type", "value": "double" },
  "actual":   { "kind": "arrow_type", "value": "string" },
  "caused_by": ["import_raw_loans"],
  "suggested_fix": {
    "kind": "cast",
    "target_node": "clean_loans",
    "column": "loan_amount",
    "cast_to": "double"
  }
}
```

Field notes:

- `caused_by` is a list of upstream node ids — this is the thing that saves an agent from
  re-deriving the DAG by hand to find the actual source of a downstream complaint. Tier 2 already
  has the whole schema-propagation graph in memory when it detects the mismatch; surfacing it costs
  nothing extra.
- `suggested_fix` is intentionally a small closed vocabulary (`cast`, `rename_column`,
  `add_node_arg`, `pin_package_version`, free-form `null` when nothing structured applies), not a
  code diff. Keeping it structured-but-small means it stays reliable across T versions; a generated
  diff would be brittle and is better left to the agent's own model call.
- `error_class` values should be a stable enum documented alongside the OCaml error variants
  (`VError` constructors), so there's a 1:1 mapping maintainers can keep honest — this is the same
  discipline as the existing golden-test regime, just extended to the JSON surface.

### 2.4 Streaming

For `t run` (which can be long-running across multiple node builds), diagnostics should stream as
newline-delimited JSON (one object per line, each tagged with `node.id` and a monotonically
increasing `seq`), not batched into one blob at the end. An agent driving a long pipeline build
wants to react to the first failing node rather than waiting for the whole DAG to fail or succeed.
`t check` (no Nix involved) can stay single-blob since it returns in milliseconds anyway.

---

## 3. Pipeline verification: why "a test suite the agent always runs" is the wrong frame

This section takes the skepticism in the prompt seriously rather than talking it out of existence,
because the skepticism is correct as stated.

### 3.1 The actual distinction

T's existing 1753 unit tests / 122 golden tests verify **the interpreter** — that `VInt + VFloat`
does the right thing, that a builtin's error message is well-formed, that the OCaml implementation
hasn't regressed. That test suite is load-bearing precisely *because* you can't review the OCaml
by eye at that volume, per your own writeup. It has nothing to say about whether a specific user's
(or agent's) pipeline is correct, and running it on every pipeline edit would be checking the wrong
layer entirely — like re-running a compiler's own test suite every time someone edits their
application code. So the instinct that this doesn't transfer is right, and building a feature that
pretends it does would be worse than building nothing.

The real question is narrower: **when an agent edits a pipeline, what signal, if any, should run
automatically, and what should stay opt-in and authored?** Three different things get conflated
under "test suite," and they have very different cost/value profiles:

### 3.2 Tier A — Structural contracts (automatic, free, on by default)

Lightweight per-node assertions about *shape*, not business logic: expected column set, expected
Arrow types (this overlaps with §1's tier-2 schema checks — contracts are the runtime-checked
version, for the parts that can't be known statically, e.g. a Python model's actual output
dtypes), row-count bounds, null-rate ceilings. These are cheap to check because they piggyback on
work T is already doing: a node only reruns when its inputs or Nix environment change (existing
Nix rebuild-on-change semantics), so the contract check only fires exactly when the node's output
could plausibly have changed. No separate schedule, no "should I run tests now" decision for the
agent to make.

```t
node clean_loans =
  r_script("clean.R") |>
  expect(columns = ["loan_id", "loan_amount", "region"],
         loan_amount ~ double(),
         null_rate("loan_amount") < 0.02)
```

This is a builtin (`expect`), not a separate test file — it lives with the node it constrains,
same way a type annotation would in a statically typed language. It fires as a normal part of
`t run`, at `phase: "exec"` in the diagnostics schema above, no extra command.

### 3.3 Tier B — Automatic output diffing (the actually novel piece)

Because every node's output is a content-addressed Nix store path, T can trivially answer "did
this node's actual output change as a result of my edit" for free — the hash either matches the
previous run or it doesn't. This is a much stronger and cheaper signal than an authored golden
test, because nobody has to write it: after any edit, `t run` (or a lighter `t diff`) can report,
per node, "unchanged / changed / new," and for changed nodes with tabular output, a structural
diff (columns added/removed, row count delta, summary-stat delta on numeric columns) rather than a
row-by-row dump.

```
$ t diff
clean_loans        unchanged
join_regions       changed   (rows: 48213 → 48198, -15)
train_model        changed   (output hash differs — model retrained)
```

This is the thing that actually answers "did my edit to node X quietly break node Y three hops
downstream," which is exactly the failure mode an agent iterating fast is most likely to introduce
and least likely to notice. It requires no test-writing effort from anyone, agent or human, and it
gets *more* valuable the more nodes a pipeline has — the opposite of authored tests, which get more
expensive to maintain as the pipeline grows.

### 3.4 Tier C — Authored pipeline tests (opt-in, not run automatically)

A `tests/*.t` convention (mirroring `targets`/`testthat`) for cases where a human or agent actually
wants to assert business-logic properties that aren't derivable from shape alone — "the join must
not drop rows for region X," "the trained model's AUC must exceed 0.7 on the holdout." This is
genuinely equivalent to a normal test suite, and it has the same property normal test suites have
for any language: it's only as good as the assertions someone bothered to write, an LLM can
absolutely write vacuous ones, and it should not be forced onto every agent edit by default,
because that reintroduces exactly the "who decides when the expensive thing runs" cost the Scarf
post is complaining about in the first place. Make it easy to invoke (`t test`, maybe wired into
`pipeline_to_ga` as an optional CI stage) and leave the decision of whether to write and run it to
the agent/human, the same way it's their decision today.

### 3.5 Summary table

| Tier | What it checks | Authoring cost | When it runs | Novel vs. existing tooling? |
|---|---|---|---|---|
| A. Contracts | Shape/type/null-rate at a node boundary | Low (one `expect()` call) | Automatically, only when node reruns | Extension of existing error-context discipline |
| B. Output diffing | Did output change, and how | **Zero** | Automatically, every `t run`/`t diff` | Yes — leverages Nix content-addressing, nobody writes anything |
| C. Authored tests | Business-logic invariants | Same as any test suite | Opt-in, on demand or in CI | No — this is just `targets`/`testthat` for T, correctly scoped as optional |

Tier B is the one worth prioritizing first: it's the only one of the three that's free to both
build the value proposition for and use, and it's the one that most directly answers the concern in
the prompt — that an interpreter-level test suite "helps hack on T but not develop a pipeline with
T." Tier B is pipeline-level by construction and costs nothing extra given the architecture T
already has.

---

## 4. Agent loop, end to end

1. Agent edits `pipeline.t`.
2. `t check --schema --json` — milliseconds, no Nix. Catches structural and schema errors, with
   `caused_by` pointing at the real upstream source.
3. If clean, `t run` (only invalidated nodes rebuild, per existing content-addressed caching).
   Tier A contracts fire inline as part of exec; any failure streams as a JSONL diagnostic at
   `phase: "exec"`.
4. `t diff` — free structural diff of what actually changed downstream, so the agent (or the
   reviewer) can see blast radius without reading node internals.
5. Tier C tests, if present, run in CI (`pipeline_to_ga`-generated workflow) or on explicit request
   — not part of the default inner loop.

---

## 5. Open questions

- Should tier-2 schema propagation handle Python/Julia nodes with the same confidence as R, given
  weaker static guarantees on the Python side (PMML/ONNX metadata may need to be the source of
  truth rather than inferred from code)?
- Where does `suggested_fix` live long-term — should it eventually become a real `t fix` command
  that applies the structured fix mechanically for the closed set of fix kinds, rather than leaving
  even that small step to the agent's model call?
- Does `--env` (tier 3) need a `--offline` guarantee mode that hard-fails rather than falling back
  to network fetch, so agents in sandboxed/parallel contexts never accidentally trigger a slow path?

---

## 6. Implementation Plan — Remaining Features

This section tracks the features from §2 (JSON diagnostics protocol) that are not yet
fully implemented, ordered by effort (lowest first). Each feature includes the scope of
changes, files to touch, test requirements, and documentation/changelog updates.

### 6.1 `target_node` field on `suggested_fix` (spec §2.3)

**Status:** Not implemented
**Effort:** ~30 min

**What:** Add an optional `target_node` field to `Cast`, `Rename_column`, and `Add_node_arg`
variants of `suggested_fix`. The spec shows `"target_node": "clean_loans"` on fix objects;
currently absent.

**Changes:**
- `src/diagnostics.ml`: Add `target_node: string option` to the three variants; update
  `suggested_fix_to_yojson` to serialize it; update `suggested_fix_of_yojson` to deserialize it.
- `src/schema_check.ml`: Thread `node_name` into the `Cast` constructor (line ~328).
- `src/fix.ml`: Update pattern matches in `apply_fix` and `apply_fixes` to ignore the new field
  (use `_` wildcards).
- `src/packages/pipeline/t_fix.ml`: Update pattern matches.

**Tests:**
- `tests/test_fix.ml`: Update `test_roundtrip` to include `target_node` in fix values and verify
  it survives JSON roundtrip.
- `tests/test_check.ml`: No changes needed (existing tests use `NoFix`).

**Docs:**
- `docs/api-reference.md`: Update `t fix` section to mention `target_node` in the JSON output
  example.
- `docs/changelog.md`: Add entry under 0.54.1.

---

### 6.2 `expected` / `actual` fields on diagnostic (spec §2.3)

**Status:** Not implemented (data exists in `schema_check.ml` but only in message string)
**Effort:** ~1 hour

**What:** Add structured `expected` and `actual` fields to the diagnostic JSON object, so agents
can branch on the specific types without parsing the human-readable message.

**Changes:**
- `src/diagnostics.ml`: Add `diag_expected: string option` and `diag_actual: string option` to
  the `diagnostic` type. Update `diagnostic_to_yojson` to serialize them as structured objects
  (`{"kind": "arrow_type", "value": "double"}`). Update all diagnostic constructors (22 sites)
  to pass `None` for the new fields.
- `src/schema_check.ml` (lines ~309–330): In the type-contract violation branch, pass
  `expected_type` and `actual_type` as `Some` values instead of only embedding them in the
  message string.
- `src/env_check.ml`, `src/eval.ml`: Pass `None` for new fields in existing constructors.

**Tests:**
- `tests/test_check.ml`: Add a test that constructs a diagnostic with `expected`/`actual` and
  verifies they appear in JSON output. Verify existing tests still pass with `None` defaults.
- `tests/test_fix.ml`: No changes needed.

**Docs:**
- `docs/api-reference.md`: Update the `t check` JSON output example to show `expected`/`actual`
  fields on a type-mismatch diagnostic.
- `docs/changelog.md`: Add entry under 0.54.1.

---

### 6.3 Centralized `error_class` enum (spec §2.3)

**Status:** Not implemented (bare strings scattered across files)
**Effort:** ~1.5 hours

**What:** Replace ~22 ad-hoc `error_class` string literals with a proper OCaml variant type,
as the spec requires a "stable enum documented alongside the OCaml error variants."

**Changes:**
- `src/diagnostics.ml`: Define `type error_class = Structural_error | Name_error | ... | NoFix`
  with `error_class_to_string` and `error_class_of_string`. Update `diagnostic` type to use
  `diag_error_class : error_class` instead of `string`.
- `src/schema_check.ml`: Replace `"schema_mismatch"`, `"contract_violation"`,
  `"contract_unverifiable"` with the new variant constructors.
- `src/env_check.ml`: Replace `"missing_tproject"`, `"missing_package"`,
  `"missing_from_lockfile"`, `"nix_generation_error"`, `"nix_eval_error"`.
- `src/diagnostics.ml`: Replace `"invalid_expect_placement"`, `"na_warning"`.
- `src/eval.ml`: Replace any bare error_class strings.
- Update `error_code_to_error_class` to return the new type.
- Update `diagnostic_to_yojson` to serialize via `error_class_to_string`.

**Tests:**
- `tests/test_check.ml`: Update `check_eq "of_verror: error_class maps to structural_error"` to
  compare against the new type. Add tests for all error_class variants.
- `tests/test_fix.ml`: No changes needed (uses `diag_error_class` but doesn't compare strings).

**Docs:**
- `docs/api-reference.md`: Update the error_class column in the JSON output documentation to list
  all valid enum values.
- `docs/changelog.md`: Add entry under 0.54.1.

---

### 6.4 `node.file` + `node.span.end` in diagnostic (spec §2.3)

**Status:** Not implemented (file is at top level, span only has `start`)
**Effort:** ~2 hours

**What:** Restructure the diagnostic JSON to match the spec's shape: `file` and full `span`
(both `start` and `end`) nested inside the `node` sub-object.

**Changes:**
- `src/diagnostics.ml`: Add `diag_end_line: int option` and `diag_end_column: int option` to
  the `diagnostic` type. Restructure `diagnostic_to_yojson` to:
  - Move `file` into the `node` sub-object.
  - Add `end` to `span` (`"span": {"start": [l, c], "end": [el, ec]}`).
- Update all diagnostic constructors to pass `None` for end line/column.
- `src/schema_check.ml`: Where line/column info is available from AST locs, thread it through.

**Tests:**
- `tests/test_check.ml`: Add test verifying the new JSON structure (node contains file, span has
  start and end). Update existing JSON structure tests.
- `tests/test_fix.ml`: No changes needed.

**Docs:**
- `docs/api-reference.md`: Update the JSON output example to show the new node shape.
- `docs/changelog.md`: Add entry under 0.54.1.

**Note:** This is a **breaking change** to the JSON output shape. The `file` field moves from
top-level to inside `node`, and `span` gains an `end` field. Agent tooling that parses the JSON
will need to update. Document this in the changelog as a breaking change.

---

### 6.5 `Add_node_arg` and `Pin_package_version` fix application (spec §2.3)

**Status:** Types exist, serialization works, but `apply_fix` returns `false` for both
**Effort:** ~3–4 hours total

**What:** Implement the mechanical application of two `suggested_fix` kinds that are currently
stubs.

**`Add_node_arg` (~1.5 hours):**
- Parse the pipeline file to find the node definition matching the target node name.
- Insert the argument (e.g., `na_rm=true`) into the node's argument list.
- Requires understanding the pipeline AST or using regex-based insertion.

**`Pin_package_version` (~2 hours):**
- Parse `tproject.toml` to find the package section.
- Update the version constraint for the specified package.
- Requires TOML manipulation (the project uses `otoml`).

**Changes:**
- `src/fix.ml`: Implement `apply_add_node_arg` and `apply_pin_package_version`. Update
  `apply_fix` to call them instead of returning `false`.
- `tests/test_fix.ml`: Add tests for both new fix applications.

**Tests:**
- `tests/test_fix.ml`: Add `test_apply_add_node_arg` and `test_apply_pin_package_version` with
  temp file fixtures.
- Verify dry-run counting works for both.

**Docs:**
- `docs/api-reference.md`: Update `t fix` section to note that all fix kinds are now supported.
- `docs/changelog.md`: Add entry under 0.54.1.

---

### 6.6 Streaming NDJSON for `t run` (spec §2.4)

**Status:** Implemented
**Effort:** ~1–2 days

**What:** Implement newline-delimited JSON streaming for `t run` diagnostics, so agents can
react to the first failing node without waiting for the whole DAG.

**Changes:**
- `src/pipeline/ndjson_stream.ml`: New module with NDJSON event types (`run_started`, `node_failed`, `node_skipped`, `run_finished`) and emitters.
- `src/ast.ml`: Added `ndjson_mode` global flag (similar to `check_mode`).
- `src/pipeline/builder_utils.ml`: Added `run_command_stream_argv_separate` for separate stdout/stderr handling.
- `src/pipeline/builder_internal.ml`: `build_pipeline_internal` reads `Ast.ndjson_mode` to emit NDJSON events, capture per-node build logs to `_pipeline/logs/<node>.log`, suppress human-readable output in JSON mode.
- `src/repl.ml`: `--json` flag added to `t run`; sets `Ast.ndjson_mode` during evaluation; suppresses Pretty_print output.

**Tests:**
- `tests/test_ndjson.ml`: Unit tests for seq counter, truncate_tail, timestamp, log paths, node_spec type, and all four emit functions (stdout capture via pipe).

**Docs:**
- `docs/api-reference.md`: Document `t run --json` streaming output.
- `docs/changelog.md`: Add entry under 0.54.1.

---

## 7. Changelog Updates for Already-Implemented Features

The following features have been implemented since 0.54.0 but are not yet fully documented
in `docs/changelog.md`. The current 0.54.1 changelog only covers `t check` environment
validation. The following entries need to be added:

### 7.1 `t check` — Full CLI & Structured Diagnostics Protocol

- **Tier 1 CLI (`t check <file>`)**: Structural pipeline validation without triggering Nix
  builds. Catches parse errors, DAG cycles, dangling node references, arity errors, and
  built-in name resolution. Exit codes: 0=clean, 1=wire error, 2=schema error, 3=env error.
- **Tier 2 Schema Validation (`t check --schema`)**: Static column-name and type propagation
  through the pipeline DAG. Validates column references against inferred upstream schemas,
  checks `expect()` type contracts, and reports contract violations with `Cast` suggested fixes.
- **Structured JSON Diagnostics (`--json`)**: Machine-readable output for all tiers, with
  `schema_version`, `status`, `phase`, `tier`, and per-diagnostic `error_class`, `severity`,
  `caused_by`, and `suggested_fix` fields. Designed for agent tooling.
- **`t_check(file, json, schema, env)` REPL function**: Invoke `t check` from within a T
  session.

### 7.2 `t diff` — Content-Addressed Output Diffing

- **`t diff <file>`**: Compares two builds of a pipeline using per-node Nix content hashes
  without loading artifacts. Reports each node as `unchanged`, `changed`, `added`, `removed`,
  or `errored`.
- **`t_diff(file, json, log_a, log_b)` REPL function**: Invoke `t diff` from within a T
  session.
- **`diff_summary(p)`**: Returns a DataFrame of per-node diff status for the two most recent
  builds.

### 7.3 `t fix` — Mechanical Suggested-Fix Application

- **`t fix <file>`**: Runs `t check --schema`, extracts diagnostics with `suggested_fix`, and
  applies them mechanically. Currently supports `Cast` (inserts `|> mutate(...)`) and
  `Rename_column` (replaces `$old` with `$new` in column references).
- **`t_fix(file, dry_run)` REPL function**: Invoke `t fix` from within a T session.
- **Word-boundary-safe rename**: Column renames only affect `$col` and `` $`col` `` forms,
  avoiding corruption of identifiers like `valid` when renaming `id`.

### 7.4 Nix Installation Documentation

- **Comprehensive Nix installation guide** (`docs/nix-installation.md`): Platform-specific
  instructions for Linux, macOS, NixOS, and WSL2. Includes Determinate Systems installer,
  manual configuration for existing Nix installs, and Docker container setup.
- **NixOS configuration**: Full `configuration.nix` snippets for trusted users, binary cache,
  and flakes.
- **Binary cache setup**: Instructions for configuring the `rstats-on-nix` Cachix cache on
  NixOS and non-NixOS systems.

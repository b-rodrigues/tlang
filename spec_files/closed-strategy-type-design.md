# Design: Closed Strategy Type (Item 2 Long Term)

**Status:** SUPERSEDED. The `custom("name")` escape described below was
removed entirely. Strategies are built-ins or strategy dicts
(`[format: ^name, ...snippets]`, closed keys) — see
`spec_files/path-to-0.55.5.md` item 2 and `docs/serializers.md`.
Kept as a historical record of the shipped-then-removed step.
**Source:** `spec_files/path-to-0.55.5.md:51` item 2, open point at line 84.
**Scope:** `serializer` and `deserializer` positions on `node`, `rn`, `pyn`, `jln`, `shn`, `qn`, `set_pipeline_global_options`.

## 1. Problem

Strategies are symbols today. Examples: `^csv`, `default`, `custom("write_pkl")`, inline `Dict`.
A typo passes parsing. It fails late. It fails at construction or at build time.
A missing table entry once emitted a bare `default(...)` call. No such builtin exists. The node spun at 100% CPU. See `src/pipeline/nix_emit_node.ml:167`.

Today has three guards. They work. They are not a type:
- Construction guard in `src/eval.ml:1151`. Bare unbound names fail with valid set and `custom()` hint.
- Validation guard in `src/pipeline/pipeline_validation.ml:309`. Unknown formats fail with `^arrow` to `^ipc` hint.
- Emitter guard in `src/pipeline/nix_emit_node.ml:213`. Known but unmapped formats raise `Invalid_argument`.

A typo still typechecks. `t check` sees `Symbol`. Any `Symbol` fits. The user learns late.

## 2. Goals

- Typos do not typecheck. `serializer = ^cvs` is a check error at the call site.
- Valid code keeps working. No script rewrite for correct pipelines.
- No parser change. No lexer change. `^csv` syntax stays.
- No runtime value change in phase 1. `VSymbol`, `VSerializer`, `VDict` stay.
- One source of truth for the closed set. Today the list lives in three places.

## 3. Non-Goals

- No new `^` names in this change.
- No removal of `Dict` custom form.
- No removal of `custom("name")` escape.
- No change to `^bin` fetchurl rule.
- No change to `text` raw bytes rule.
- No automatic fix of typos. `t fix` stays manual for strategies.

## 4. Proposal (Recommended)

Add a static type `Strategy`. Use it in signatures. Check it at `t check`.

### 4.1 New static type

- Add `TStrategy` in `src/semantic_type.ml`. Add `Ast.Strategy` in type syntax if needed. Map spelling `Strategy` in `from_string`, like the `DataFrame` fix.
- Add runtime kind name `Strategy` in `Ast` type name function, next to `VSerializer` at `src/ast.ml:355`.
- Document: `Strategy = Builtin | CustomQuote | InlineDict`. Builtin is the closed list. CustomQuote is `custom("name")`. InlineDict is a `Dict` with a `format` key.

### 4.2 Signature change (docs only, then checker)

- Change `--#` signatures from `Symbol | Dict` to `Strategy`. Files: `src/packages/pipeline/node_docs.ml:21`, `rn_docs.ml`, `pyn_docs.ml`, `jln_docs.ml`, `shn_docs.ml`, `qn_docs.ml`.
- Keep runtime acceptance wide in phase 1. Only the static checker gets strict. This avoids breaking the REPL permissive mode.

### 4.3 Inference rules for `t check`

- `^csv`, `^ipc`, `^parquet`, `^json`, `^pmml`, `^onnx`, `^bin`, `^text`, `^tlang`, `default`, `serialize` infer to `Strategy`. Only if the name is in `known_serializer_formats` at `src/pipeline/pipeline_validation.ml:297`.
- `custom("name")` returns `Strategy`. Today it returns `Symbol` at `src/packages/pipeline/custom_strategy.ml:15`. Change the doc return to `Strategy`. Keep the runtime value as `VSymbol` in phase 1.
- Inline `Dict` with a `format` key infers to `Strategy`. Other `Dict` values do not.
- A `Var` holding one of the above infers to `Strategy` only if the checker can see the binding. Unknown `Var` does not infer to `Strategy`. It warns or errors at the `node()` call site.
- `String` literals never infer to `Strategy`. This keeps the current `validate_no_strings` rule.

### 4.4 Single source of truth

- Move the closed list to one module. Candidate owner: `Pipeline_validation.known_serializer_formats`.
- The construction guard at `src/eval.ml:1151`, the validation guard at `src/pipeline/pipeline_validation.ml:309`, the emitter table at `src/pipeline/nix_emit_node.ml:167`, the `custom` docs at `src/packages/pipeline/custom_strategy.ml:6`, and the new checker all read the same list.
- Add a unit test that asserts all five lists match. Today they can drift.

### 4.5 Error message

- Keep the current words. Name the bad value. Name the valid set. Teach the escape.
- Example: `Unknown strategy 'cvs' for 'serializer'. Valid built-in formats: ^bin, ^csv, ... For a custom function, quote it: custom("cvs") and declare it in 'functions'.`
- Keep the `^arrow` hint: `Did you mean ^ipc? (^arrow was renamed to ^ipc in 0.55.0 with no alias.)`

## 5. What Changes for Users

Before:
```t
p = pipeline {
  a = node(command = 1, serializer = ^cvs)
}
```
Today: passes parsing. Fails at construction or validation with `TypeError`.

After:
```t
p = pipeline {
  a = node(command = 1, serializer = ^cvs)
}
```
After: `t check` reports a type error at the `serializer` argument. It names the valid set. Build never starts.

Valid code is unchanged:
```t
a = node(command = 1, serializer = ^csv)
b = node(command = 1, serializer = custom("write_pkl"), functions = ["s.py"])
c = node(command = 1, serializer = [format: "my-ext", write: \(p, v) 1])
s = ^csv
d = node(command = 1, serializer = s)
```

## 6. What Changes for Code

Phase 1 (this design, no parser change):
- `src/semantic_type.ml`: add `TStrategy`, parse `Strategy`, structural compare.
- `src/typecheck.ml` or analyzer call check: `serializer` and `deserializer` arguments must be `Strategy`-compatible. Unknown `Symbol` or unknown `Var` is an error. `TUnknown` from error paths stays compatible, like `VError` bottom rule.
- `--#` blocks: change `Symbol | Dict` to `Strategy` in six doc files.
- Coverage audit: `Strategy` counts as precise, like `DataFrame` fix. Expect count rise with zero new rejections on valid suite.
- Tests: extend `tests/pipeline/test_strategy_closed.ml:22`. Add `t check` tests for `^cvs`, bare `write_pkl`, `custom("write_pkl")` pass, `s = ^csv` pass, unknown `Var` fail.

Phase 2 (later, needs second approval):
- Optional runtime wrapper `VStrategy`. Wrap `VSymbol` and `VSerializer` at `node()` construction. Emitter matches only on `VStrategy`. This removes the string fallback path fully.
- Not part of this design approval. Propose it after phase 1 ships.

## 7. Alternatives Rejected

- New syntax `strategy(csv)`: needs parser change. Breaks all scripts. Rejected.
- Stringly typed fix only: adds more guards but typos still typecheck. Does not meet the goal. Rejected.
- Auto-correct typos in `t fix`: risky. `^cvs` could mean `^csv` or `^vs` custom. Keep manual. Rejected for now.
- Grandfather bare names with `functions` backing: current code already allows `functions`-backed custom names at validation. Keep that. Do not allow bare names without `custom()`. Grandfathering hides typos. Rejected, same as shipped 0.55.5 rule.

## 8. Risks

- False rejections on `Var` indirection. Mitigation: allow `Var` bound to a known `Strategy` in the same file. Reject only unbound or non-strategy `Var`. Add tests at `tests/pipeline/test_strategy_closed.ml:52` shape.
- `jln_docs.ml` today says `Symbol` only. It omits `Dict` and `custom()`. Unify it with `node_docs.ml` before the checker goes strict. Else valid Julia custom strategies fail.
- `set_pipeline_global_options` docs say `String | Symbol`. Unify to `Strategy` too.
- Coverage audit floor must move. Ratchet it after the batch, with full suite green.

## 9. Acceptance

- `t check` fails on `serializer = ^cvs` at the argument site. Message names the valid set and the `custom()` escape.
- `t check` fails on `serializer = write_pkl` (bare). Message teaches `custom("write_pkl")`.
- `t check` passes on `^csv`, `default`, `custom("x")` with `functions`, inline `Dict` with `format`, and `s = ^csv` indirection.
- `dune runtest` is green. No new rejection on valid programs.
- Emitter test still asserts no bare `name(...)` call path. Single list test asserts all modules agree.
- Docs regenerated: `t doc --parse --generate`, `docs/api-reference.md`, `summary.md` if user-facing.

## 10. Sequencing

1. Maintainer approves this file. No code before approval.
2. Phase 1: static type + signatures + `t check` rule + tests. No parser change.
3. Run `dune build`, `dune runtest`, docs audit, coverage audit.
4. Phase 2 proposal later: runtime `VStrategy` wrapper, if wanted.

## 11. Approval Ask

Approve phase 1: nominal closed static type `Strategy`, signature change to `Strategy`, `t check` enforcement at strategy positions, single list owner, no parser or runtime value change.
If you want phase 2 now, say so. Else phase 2 needs a second design.

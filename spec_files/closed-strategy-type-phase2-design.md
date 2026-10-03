# Design: Runtime Strategy Wrapper (Phase 2)

**Status:** SUPERSEDED. Implemented differently: no `VStrategy` wrapper
was added and no `custom()` value change happened, because `custom()`
was removed entirely instead. The closed dict shape is enforced in
`pipeline_validation.check_known_formats`; the emitter fails loud on
unknown formats. Kept as a historical record.
**Parent:** `spec_files/closed-strategy-type-design.md` phase 1 (static `Strategy`, shipped as docs plus permissive check).
**Source:** `spec_files/path-to-0.55.5.md:84` long term point.

## 1. Problem

Phase 1 added a static name. Runtime still uses three shapes. `VSymbol`, `VSerializer`, `VDict` all mean strategy in different code paths.
Each consumer repeats the same decode. See `src/pipeline/nix_emit_node.ml:33`, `src/pipeline/pipeline_validation.ml:315`, `src/pipeline/builder_populate.ml:126`.
A missed case falls through to raw text. That class once hung nodes at 100% CPU.

Custom intent is implicit. `custom("write_pkl")` returns `VSymbol "write_pkl"` at `src/packages/pipeline/custom_strategy.ml:24`. A typo is also `VSymbol`. Only pipeline context (`functions` backing) tells them apart. `Ast.is_compatible` has no context. It must stay permissive.

## 2. Goals

- One runtime value for strategies. Consumers match once. No string fallback.
- Custom intent is explicit in the value, not in context.
- Unknown shapes fail loud at construction, not at build time.
- No syntax change. `^csv`, `default`, `custom("name")`, inline `Dict` all keep working.
- Zero new rejections on valid programs and valid custom strategies.

## 3. Non-Goals

- No new `^` names.
- No removal of `Dict` custom form.
- No auto-fix of typos.
- No change to `^bin` fetchurl rule.
- No change to `text` raw bytes rule.
- No JSON support for strategies (`src/serialization.ml:302` stays unsupported).

## 4. Proposal

Add `VStrategy` in `src/ast.ml`, next to `VSerializer` at line 355. Wrap at `node()` construction. Consumers match only `VStrategy`.

### 4.1 New value

```ocaml
and strategy_kind =
  | StratDefault
  | StratBuiltin of string
  | StratCustom of string
  | StratInline of (string * value) list
```

- `StratDefault`: bare `default` sentinel.
- `StratBuiltin`: known format from `Pipeline_validation.known_serializer_formats` at `src/pipeline/pipeline_validation.ml:297`. Stores canonical lowercase form without `^`.
- `StratCustom`: name from `custom("name")` or a `Var` indirection that resolved to a custom quote. Stores raw name.
- `StratInline`: inline `Dict` pairs. Must contain a `format` key, like today at `src/pipeline/pipeline_validation.ml:342`.

`value` gains `| VStrategy of strategy_kind`.

### 4.2 Wrap point

Wrap in `lookup_serializer_arg` at `src/eval.ml:1151`, after `validate_no_strings`. Today it returns `Value v`. After, it returns `Value (VStrategy kind)` for strategy positions only.

Mapping, in order:
1. `VSerializer s` with known `s_format` maps to `StratBuiltin s.s_format`.
2. `VSymbol s`: strip `^`, lowercase. If known, map to `StratBuiltin`. Else if it came from `custom()` call or a `Var` bound to a `custom()` result, map to `StratCustom`. Else keep current error path (unknown strategy with valid set and escape). Do not silently pass through.
3. `VDict pairs` with `format` key maps to `StratInline pairs`. `VDict` without `format` keeps current behavior (today `get_format` returns `None`; validation ignores non-format dicts; decide: error with clear message).
4. `VString` keeps current error (strings are not allowed, see `validate_no_strings` at `src/eval.ml:1142`).
5. `Var` unbound keeps current error at `src/eval.ml:1160`. `Var` bound to a strategy value unwraps to that value, then wraps.

How to know `custom()` origin: `custom()` today returns plain `VSymbol`. Change `custom()` to return `VStrategy (StratCustom name)` directly at `src/packages/pipeline/custom_strategy.ml:24`. Then step 2 never confuses typo `VSymbol` with quoted custom. This is the one runtime value change. It is safe because all strategy consumers will match `VStrategy` after this design.

`^csv` eval at `src/eval.ml:1024` returns `VSerializer` today when in registry. Keep it. Wrap step maps it to `StratBuiltin`. Missing registry entries (`default`, `serialize`) stay `VSymbol`, then wrap step maps known ones to `StratBuiltin`. Add missing registry entries instead if cleaner: register `default` and `serialize` in `src/serialization_registry.ml:59` list. Prefer registry add plus wrap. Both small.

### 4.3 Consumer updates (all required, same batch)

- `src/pipeline/nix_emit_node.ml:33` `get_format`: match `VStrategy` only. `StratBuiltin f` and `StratDefault` resolve via `io_fns` table at line 167. `StratCustom name` passes through as custom function name. `StratInline pairs` reads `format` plus snippets like today at line 52. Any other value raises `Invalid_argument` naming the valid set. Delete the `VString | VSymbol | VDict` fallback arms.
- `src/pipeline/pipeline_validation.ml:315` `unknown_in`: match `Value (VStrategy ...)`. `StratBuiltin` checks membership. `StratCustom` checks `has_functions name`, else error naming `custom()` plus `functions`. `StratInline` skips `format` key like today. `Var` case stays for indirection the checker cannot see through. Delete raw `VString | VSymbol` arms (strings already rejected at construction).
- `src/pipeline/builder_populate.ml:126` `requires_functions`: `StratCustom` needs `functions`. `StratBuiltin` does not. `StratInline` does (snippets come from dict). Keep the warning text.
- `src/pipeline/nix_unparse.ml:39`: `VStrategy` prints as `^format`, `custom("name")`, or dict text. Round-trip must hold: parse of printed form gives same kind.
- `src/packages/explain/t_explain.ml:446`: show `VStrategy` like `VSerializer` today.
- `src/repl.ml:290`: pretty print `VStrategy` as `strategy<^csv>` or `strategy<custom("w")>`.
- `src/ast.ml:1839` `type_name`: `VStrategy` gives `"Strategy"`. `is_compatible` at line 2520 already accepts `VSymbol | VSerializer | VDict` for `TCustom "Strategy"`. Extend it to accept `VStrategy` (all kinds). Keep old arms during migration, delete after.
- `src/packages/base/fetchurl.ml:51`: `VStrategy` maps to `"^format"`. Today it matches `VSerializer`.
- `src/packages/pipeline/set_pipeline_global_options.ml:123`: pass through `VStrategy` like `VSerializer` today.
- `src/packages/testcraft/t_expect_pipeline.ml:22`: compare `VStrategy` canonical form.
- `src/packages/core/t_boolean.ml:185` equality: `VStrategy` compares by kind. Same kind and same payload is equal.
- `src/diff.ml:620`: `VStrategy` equality same rule.
- `src/serialization.ml:302`: keep `VStrategy` unsupported for JSON, like `VSerializer` today. Explicit error stays.

### 4.4 Single list

`Pipeline_validation.known_serializer_formats` stays the owner. Registry list at `src/serialization_registry.ml:59`, emitter `io_fns` keys at `src/pipeline/nix_emit_node.ml:167`, `known_symbols` strategy entries at `src/packages/core/packages.ml:764` all derive from it or are tested equal. Add one test that asserts equality. Today they drift (`known_symbols` lacks `^text`, `^tlang`, `^json`; registry lacks `default`).

## 5. Examples

No user syntax change.

```t
a = node(command = 1, serializer = ^csv)
b = node(command = 1, serializer = default)
c = node(command = 1, serializer = custom("write_pkl"), functions = ["s.py"])
d = node(command = 1, serializer = [format: "my-ext"])
s = ^csv
e = node(command = 1, serializer = s)
```

After wrap, `a` holds `VStrategy (StratBuiltin "csv")`. `c` holds `VStrategy (StratCustom "write_pkl")`. `d` holds `VStrategy (StratInline [...])`.

Errors stay the same words:
- `serializer = ^cvs` fails at construction. Names valid set.
- `serializer = write_pkl` bare fails. Teaches `custom("write_pkl")`.
- `serializer = "csv"` string fails. Says use `^csv`.

## 6. Migration

Order matters. Land in one batch so no half state ships:
1. Add `strategy_kind` and `VStrategy` in `src/ast.ml`. Add `type_name`, pretty print, equality, `is_compatible` accept. Keep old arms.
2. Change `custom()` to return `VStrategy (StratCustom name)`.
3. Wrap at `lookup_serializer_arg`. Register missing `default` in registry if chosen.
4. Update all consumers listed in 4.3. Delete old fallback arms last.
5. Update `--#` docs if needed (phase 1 already says `Strategy`).
6. Regenerate reference: `t doc --parse --generate`.

## 7. Risks

- `custom()` return change breaks tests that assert `custom("x")` prints as `write_pkl` symbol. See `tests/pipeline/test_strategy_closed.ml:13`. Update them to expect strategy print. Keep one test that the quoted name still resolves in `functions` builds.
- `Var` indirection: `s = ^csv` then `serializer = s` must still work. Wrap step must resolve bound `Var` before matching. Test exists at line 52. Keep it.
- `Dict` without `format`: decide error vs ignore before coding. Today it is ignored in validation but `get_format` gives `None`. Propose explicit error. If maintainer prefers ignore, keep ignore and note it here.
- Stored pipelines: `cn_serializer` is a string at `src/ast.ml:193`. Unaffected. `p_serializers` stores `expr`. After wrap the expr holds `Value (VStrategy ...)`. Old stored expressions with `Value (VSymbol ...)` only exist in memory during a run, not on disk. No migration of stored artifacts needed. Confirm with a round-trip test.
- `VSerializer` stays for `^csv` value eval and registry. Do not delete it. `VStrategy` wraps intent; `VSerializer` keeps reader and writer functions.

## 8. Tests

- Extend `tests/pipeline/test_strategy_closed.ml`: construction still rejects bare names, strings, unknown caret. `custom()` returns strategy kind. `Var` indirection passes. `Dict` with and without `format`. `default` passes.
- New single-list test: registry names, `io_fns` keys per runtime, `known_symbols` strategy entries, `known_serializer_formats` all agree (modulo documented legacy `serialize` spelling).
- Emitter tests: per-runtime `not (has "= default(")` assertions stay. Add: no emitter path matches non-`VStrategy` without raising.
- Unparse round-trip: print then parse gives same kind for builtin, custom, inline, default.
- Full `dune runtest` green. Coverage audit floor unchanged or up. Zero new rejections on valid suite.

## 9. Acceptance

- Every strategy consumer matches `VStrategy` only. No `VString | VSymbol` fallback arm remains in `get_format`, `unknown_in`, or `requires_functions`.
- `t check` tier 1 still reports unknown strategies with valid set and `custom()` hint, plus `^arrow` to `^ipc` hint.
- Valid pipelines unchanged: builtins, `default`, `custom()` with `functions`, inline dicts, `Var` indirections all build.
- One test pins the single list. It fails on drift.

## 10. Approval Ask

Approve phase 2: new `VStrategy` value with four kinds, wrap at `lookup_serializer_arg`, `custom()` returns `VStrategy`, all consumers in 4.3 updated in one batch, single list test, no syntax change.
Open question for maintainer: `Dict` without `format` is an explicit error or ignored (current). Pick one before coding.

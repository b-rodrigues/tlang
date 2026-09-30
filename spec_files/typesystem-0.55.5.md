# Type System: What Is Missing for a Full System (0.55.5)

Status of T's type system as of 0.55.4, what is missing, and in what order
to build it. Companion to `path-to-0.55.5.md` item 6 (error-aware types,
done separately): this file covers the structural gaps.

Status convention: `- [ ]` open, `- [x]` done.

## What exists today

- Annotations on lambdas (`\(x: Int -> Int)`), checked at runtime.
- Strict mode (scripts, `t check`) versus permissive REPL mode.
- `types_compatible`: asymmetric numeric widening (`Int` fits `Float`,
  not vice versa), `Any`/`TVar` match everything.
- `is_compatible` (value vs annotation): `NA` and `VError` are bottom,
  compatible with everything.
- `infer_type` in the analyzer: real rules for verbs (`select` narrows,
  `mutate` extends, `filter`/`arrange` pass through), `read_csv` headers;
  everything else falls back to `TUnknown`/`TAny`.
- Generics parse (`\(T)(x: T -> T)`), undeclared type variables are caught;
  `TVar` never unifies (see item 1).

## 1. Generic instantiation

**Problem.** Syntax exists (`\(T)(x: T -> T)`) and undeclared names are
caught, but calls never checked consistency: `const(1, "s")` passed
silently.

**Direction.**
- [x] Runtime use-site consistency (done): a type variable occurring in
  several parameter positions must receive the same *kind* of value.
  Compared by type head only (constructors, payloads ignored), so the
  check can never reject two values of the same kind; custom types
  compare by name (`Model` vs `Pipeline` differ). Flexible positions
  (`Any`, including reified `NA` and error values) neither bind nor
  constrain: the first *solid* value wins, so `(NA, 1, "s")` and
  `(1, "s", NA)` agree. Nested type variables (e.g. inside `List[T]`)
  are not unified. The static analyzer has no call checking to extend,
  so runtime is the only layer changed. Note: `Int` vs `Float` counts
  as inconsistent here even though `types_compatible` widens — widening
  answers "does this fit", consistency asks "are these identical", and
  silent numeric merging would be the wrong default.
- [ ] Definition-site checking (body vs declared generic return) stays
  future work; the analyzer records parameter types as unknown today.

**Acceptance.**
- [x] `const(1, "s")` and `const("s", 1)` fail with the inconsistent-types
  error; consistent, single-use, `NA`-first, and `NA`-middle calls pass;
  `const(1, 2.5)` fails (documented strictness); full suite green
  with no new rejections on existing programs.

## 2. User-defined types

**Problem.** No sum types, records, or aliases. All structured domain data
travels as unshaped `Dict`s. Users cannot name their domain types.

**Direction.**
- [ ] Design doc first (maintainer approval — new syntax by nature):
  minimal shape that covers tagged unions for `match` (item 3) and named
  records for DataFrame-adjacent data.
- [ ] No code before the design is approved.

**Acceptance.**
- [ ] Approved design doc; implementation tracked separately.

## 3. Exhaustiveness of `match`

**Problem.** Missing a case is silent. There is no totality check, even
for constructors the checker already knows.

**Direction.**
- [x] Family-level check (done): `Check_utils.match_exhaustiveness_diagnostics`
  warns when the scrutinee is syntactically known to be an Error value
  (`error(...)` call or Error literal) or an NA literal and the arms lack
  the matching family pattern (`Error { ... }`, `NA`) plus any catch-all
  (`_` or variable). Unknown scrutinees (variables, general calls,
  other literals) stay silent. Per-code or per-variant exhaustiveness
  needs pattern syntax that names codes, which does not exist yet.
- [ ] Needs item 2 for user-defined constructors to be worth much; the
  error-code and NA families are covered at family level now.

**Acceptance.**
- [x] A `match` on a known Error value without an Error arm warns, and a
  `match` on a known NA value without an NA arm warns; existing suite has
  no new warnings (Int and variable scrutinees stay silent).

## 4. Variable rebinding

**Problem.** `x: Int = 1` followed by `x := "hello"` is silently allowed:
`Reassignment` never consults the original annotation, so the name lies
about its type for the rest of the scope.

**Direction.**
- [x] Check `:=` against the established annotation (done): shared
  `Check_utils.annotation_diagnostics` walks top-level statements with a
  declared-contract map (fresh `=` records or drops it, `rm()` drops it,
  `:=` warns on mismatch). Warns once, on the offending line — never on
  the original binding. The old inline copies in `repl.ml` and the test
  suite are deleted; both call the shared helper and cannot drift.
  Implemented statically (Warning, like all annotation checks) rather
  than at runtime: annotations are not retained in the value environment,
  and a value-based check would wrongly reject `Any`-annotated rebinds.
- [x] `NA`/`Error` keep passing (bottom rules already do).

**Acceptance.**
- [x] `t check` warns on `x: Int = 1; x := "hello"` (once, line 2);
  silent for `x := 2`, `x: Any` rebinds, shadowing, and `rm` cases;
  full suite green.

## 5. Builtin coverage

**Problem.** Only verbs have real inference rules. Hundreds of builtins
fall back to `TAny` from doc strings, so most call sites check nothing
statically. Sound (never wrong) but toothless.

**Direction.**
- [x] Audit first (done): a coverage test in `test_typing_mode.ml`
  parses `--#` signatures (same path as `t doc --parse`) and reports
  fully-precise/precise-return/undocumented counts per run, with a
  ratcheting floor. Baseline 2026-09-30: **79/532 fully precise, 163
  precise returns, 31 without docs**; after collection vocabulary:
  **160/532, 266 returns**; after nominal domain types: **273/532, 355
  returns**; after documenting the 31 helper-generated builtins (chrono
  parsers/ctors/extractors/predicates, `env_var_lens`): **308/532, 389
  returns, 0 without docs**. Skips gracefully outside a source
  checkout. Parsing runs inside registry save/restore so entries never
  leak into other tests (this caught a real pollution failure against
  the pre-docs `args` fallback test).
- [x] Nominal domain types (done): `Pipeline`, `Model`, `NDArray`,
  `Symbol`, `Date`, `Datetime`, `Formula`, `Lens`, `Expect`,
  `ComputedNode`, `NodeDef`, `Period`, `Duration`, `Interval` map to
  same-named `TCustom` (matching the runtime `TCustom` arms where they
  exist, e.g. `NDArray`, `Pipeline`). Deliberately excluded: `Function`
  (arity lives in `TFunction`), `Error`/`Null` (descriptive positions,
  not contracts).
- [x] Vocabulary for collections (done): `Semantic_type` gains `TList`,
  `TVector`, `TDict` (element-typed); `from_string` parses `List[X]` /
  `Vector[X]` / `Dict[K, V]` (bare names default sanely); `TUnion`
  carries top-level `A | B` docstring unions member-wise (empty segments
  dropped, `Any` absorbs); `to_ast_typ` maps onto `Ast.TList`/`TDict`
  (`Vector` checks as `List`, matching runtime); `types_compatible`
  recurses structurally with `None`-wildcard and nested widening.
  Coverage moved 79 → 160/532 (266 returns) with zero new rejections on
  the full suite, then to 273/532 with nominals.
- [x] First fill-in batch (done): the 31 undocumented helpers (chrono
  parsers/ctors/extractors/predicates, `env_var_lens`), each with
  signatures verified against implementations, doc examples executed,
  and mistype tests for representative ctors/extractors/parsers.
  Coverage now 308/532 with 0 without docs.
- [ ] Then fill in package by package for the imprecise remainder
  (mostly unions absorbed to `Any` and explicit-`Any` params — honest
  imprecision, each needs individual review).

**Acceptance.**
- [x] Coverage number moves and is re-measurable with the audit command.
- [ ] Zero new rejections on the existing suite per merged batch.

## 6. Fallibility in signatures

**Problem.** No signature says "this can fail". Callers cannot see
fallibility; covered conceptually by patho item 6 (bottom-compatible
errors) but not written on any function.

**Direction.**
- [ ] Document fallible functions in `--#` blocks as they are touched
  (ongoing, per function); prefer the `Expect_*` vocabulary at
  boundaries. No new syntax without a separate approved design.

**Acceptance.**
- [ ] Every function touched for other reasons gains the note; nothing
  invented.

## Sequencing

1. Item 4 (done this pass) — smallest, sharpest, fully testable.
2. Item 5 audit (next) — no behavior change, produces the work queue.
3. Item 1 (unification) — bounded, high value once audit shows call-site
   volume through generic functions.
4. Items 2 and 3 — design-first, maintainer approval required.
5. Item 6 — ongoing alongside all other work.

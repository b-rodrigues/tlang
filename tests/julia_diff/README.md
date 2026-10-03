# Julia differential fixtures

Each `case_NN_*.jl` is a minimal Julia snippet exercising one rule of
T's Julia dependency scanner (quotes, interpolation, transpose,
scopes, macros). The matching `case_NN_*.txt` is Julia's own truth
for that snippet (line 1: sorted unique read symbols, line 2: sorted
unique top-level binds), produced by `dump_symbols.jl` with
`Meta.parseall` (Julia version in `JULIA_VERSION`) and checked in so
the suite stays hermetic: no Julia binary, startup file, depot, or
network is needed at test time.

`tests/test_julia_diff.ml` checks two directions:

- Reads: every ASCII name in truth must be visible to T. Missing
  names are dropped reads (the silent direction) and fail. Extra
  names on T's side are safe over-approximation.
- Binds: T must not bind more than truth binds unconditionally at
  top level. Over-binding drops later reads. Under-binding only
  keeps extra edges and passes.

Truth is filtered to ASCII identifiers: T node names and T's
identifier scan are ASCII-only (`src/lexer.mll` ident_start), so
Unicode names can never form edges. `case_16_unicode` is
`z = β' * src`: it exercises the transpose fix (the `'` after `β`
must not swallow `* src`) while only `src` and `z` count.

Missing-breakage coverage: `case_19` triple transpose (`A'''`),
`case_20` `return '"'` (quote after a reserved word opens a literal),
`case_21` Unicode operator (`≠`), `case_22` `try`/`finally`,
`case_23` `abstract type`, `case_24` `abstract type` inside a
`module` (the old frame-pop bug: truth binds only `M`).

Regenerate the truth after editing any `.jl` file:

```
scripts/regen_julia_diff.sh
```

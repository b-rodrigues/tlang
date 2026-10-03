# Julia differential fixtures

Each `case_NN_*.jl` is a minimal Julia snippet exercising one rule of
T's Julia dependency scanner (quotes, interpolation, transpose,
scopes, macros). `tests/test_julia_diff.ml` parses every fixture twice
— once with T's scanner, once with Julia's own parser
(`dump_symbols.jl`, Base Julia only) — and checks two directions:

- Reads: every ASCII name Julia sees must be visible to T. Missing
  names are dropped reads (the silent direction) and fail. Extra
  names on T's side are safe over-approximation.
- Binds: T must not bind more than Julia binds unconditionally at
  top level. Over-binding drops later reads. Under-binding only
  keeps extra edges and passes.

Truth is filtered to ASCII identifiers: T node names and T's
identifier scan are ASCII-only (`src/lexer.mll` ident_start), so
Unicode names can never form edges. `case_16_unicode` is now
`z = β' * src`: it exercises the transpose fix (the `'` after `β`
must not swallow `* src`) while only `src` and `z` count.

Missing-breakage coverage: `case_19` triple transpose (`A'''`),
`case_20` `return '"'` (quote after a reserved word opens a literal),
`case_21` Unicode operator (`≠`), `case_22` `try`/`finally`,
`case_23` `abstract type`, `case_24` `abstract type` inside a
`module` (the old frame-pop bug: truth binds only `M`).

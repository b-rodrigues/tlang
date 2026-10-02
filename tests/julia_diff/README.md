# Julia differential fixtures

Each `case_NN_*.jl` is a minimal Julia snippet exercising one rule of
T's Julia dependency scanner (quotes, interpolation, transpose,
scopes, macros). `tests/test_julia_diff.ml` parses every fixture twice
— once with T's scanner, once with Julia's own parser
(`dump_symbols.jl`, Base Julia only) — and requires every name Julia
sees to be visible to T. Missing names are dropped reads (the silent
direction) and fail the test; extra names on T's side are safe
over-approximation (keywords, field names, backtick contents).

`case_16_unicode` is truth-only: T's identifier scan is ASCII-only, so
`β` is invisible to it. The fixture is dumped but skipped in the
comparison until Unicode identifiers are supported (dropping a real
read silently would otherwise fail the suite).

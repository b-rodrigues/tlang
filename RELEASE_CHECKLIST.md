# Release Checklist — T Alpha v0.1.0

> Pre-release verification steps for the T Language Alpha release

---

## 1. Test Verification

- [ ] All OCaml unit tests pass (`dune test`)
- [ ] Golden tests pass — T outputs match R/dplyr expected results (`make golden`)
- [ ] Arrow integration tests pass (native FFI + pure OCaml fallback)
- [ ] Edge case tests pass (grouped operations, window functions, formulas, error recovery)
- [ ] Large dataset tests pass (1000+ rows, 200+ unique groups)
- [ ] Performance tests pass (10k, 100k, 1M row operations complete without OOM)

## 2. Performance Benchmarks

- [ ] Column selection on 100k rows completes in <1s
- [ ] Aggregation on 100k rows completes in <1s
- [ ] Group-by + summarization on 100k rows completes in <1s
- [ ] All operations on 1M rows complete in <10s
- [ ] Memory usage <2GB for 1M row dataset
- [ ] Record benchmark results for release notes

## 3. Feature Completeness

- [ ] Six core colcraft verbs: `select`, `filter`, `mutate`, `arrange`, `group_by`, `summarize`
- [ ] Window functions: ranking (`row_number`, `min_rank`, `dense_rank`, `cume_dist`, `percent_rank`, `ntile`), offset (`lag`, `lead`), cumulative (`cumsum`, `cummin`, `cummax`, `cummean`, `cumall`, `cumany`)
- [ ] Formula interface: `y ~ x` syntax with `lm()` linear regression
- [ ] CSV I/O: `read_csv()` with options (sep, skip_lines, skip_header, clean_colnames), `write_csv()` with custom separator
- [ ] Pipeline system: DAG-based execution with dependency resolution, cycle detection
- [ ] NA handling: typed NA values, `na_rm` parameter in aggregation functions
- [ ] Error system: structured errors, actionable messages, maybe-pipe (`?|>`) for recovery
- [ ] Arrow backend: zero-copy column views, vectorized compute, hash-based grouping
- [ ] REPL: multi-line input, pretty-printing, `explain()` introspection

## 4. Documentation

- [ ] `spec_files/ALPHA.md` — Release notes up to date
- [ ] `spec_files/README.md` — Feature list and examples current
- [ ] `docs/language_overview.md` — Complete language reference
- [ ] `docs/data_manipulation_examples.md` — Practical examples
- [ ] `docs/formulas.md` — Formula syntax reference
- [ ] `docs/pipeline_tutorial.md` — Pipeline guide
- [ ] `docs/performance.md` — Performance expectations documented

## 5. Examples

- [ ] `examples/ci_test.t` — Integration test runs successfully
- [ ] `examples/data_analysis.t` — End-to-end analysis works
- [ ] `examples/pipeline_example.t` — Pipeline features demo
- [ ] `examples/statistics_example.t` — Math and statistics demo
- [ ] `examples/error_recovery.t` — Error recovery with maybe-pipe

## 6. Build and Distribution

- [ ] `nix build` succeeds cleanly
- [ ] `nix run github:b-rodrigues/tlang` works from a clean environment
- [ ] `dune build` succeeds with and without Arrow C GLib
- [ ] CI pipeline passes on all supported platforms
- [ ] Version numbers updated in documentation

## 7. Release

- [ ] Write release announcement
- [ ] Tag release in git (`v0.1.0-alpha`)
- [ ] Update project website (`docs/index.html`)
- [ ] Verify tag is accessible: `nix run github:b-rodrigues/tlang/v0.1.0-alpha`

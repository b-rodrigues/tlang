# Manual Validation Checklist: Version 0.53.0 "L'Initiation"

## Dynamic Pattern Branching

### Cross-runtime branch execution
- [ ] R runtime `map_pattern` / `cross_pattern` branches build and execute (each branch runs as R, not T)
- [ ] Python runtime `map_pattern` / `cross_pattern` branches build and execute
- [ ] Non-T branches produce correct output (verify with `build_log_to_frame` + filter, not `read_node`)
- [ ] Branches inherit the correct runtime from their parent node (`p_runtimes` propagation)

### Pattern expansion — auto-expansion on builtins
- [ ] `build_pipeline(p)` on a patterned pipeline succeeds (auto-expands) — no "call expand_pipeline first" error
- [ ] `populate_pipeline(p)` auto-expands without error
- [ ] `chain(p1, p2)` where p1 has patterns — auto-expands both
- [ ] `parallel(p1, p2)` where p1 has patterns — auto-expands both
- [ ] `union`, `intersect`, `difference`, `patch` on patterned pipelines — auto-expand

### Cross-pattern chaining
- [ ] `cross_pattern(map(a), map(b))` produces N×M branches (e.g. 2×3=6)
- [ ] Chained `cross_pattern` → `map_pattern`: `d_branch_i` depends on exactly `c_branch_i` (not "some branch of c")
- [ ] Build log shows correct dependency edges between chained branches

### Raw code substitution (`substitute_vars_in_expr`)
- [ ] `map_pattern(dep)` inlines the correct value for each branch — verify exact string equality (e.g. `"10 * 2"`, not `"param_1"`)
- [ ] Word-boundary `\b` safety: dep named `a` does NOT replace `aa` or `a_b` in command body
- [ ] Cross-runtime substitution works (R, Python, Julia, Shell nodes — only parser-identified `raw_identifier` names are replaced)

### Ref-cell wiring (expand_for_build)
- [ ] All 6 composition/set-op builtins (chain, parallel, union, intersect, difference, patch) on a patterned pipeline do NOT return "expander not yet installed"

## Static DAG Conditionals

- [ ] `node_when(false, node_val)` — node excluded from DAG (not present in `pipeline_nodes`, not built)
- [ ] `node_when(true, node_val)` — node included (built normally)
- [ ] `node_fork(cond1, val1, cond2, val2, .default = val3)` — selects first matching branch
- [ ] `node_fork` with no matching condition and no `.default` — returns error

## VDataFrame JSON Interchange

- [ ] Cross-runtime pipeline with VDataFrame dependency between non-T nodes succeeds (JSON interchange works)
- [ ] NAColumn-containing DataFrames serialize without errors (NA columns omitted from JSON output)
- [ ] DictionaryColumn and ListColumn values survive JSON round-trip

## Demos / Integration Tests

- [ ] `t_demos/dynamic_branching_t`: cross_pattern → map_pattern with R ggplot2 → builds and renders
- [ ] `t_demos/pipeline_to_ga_demo_t`: builds without "Pipeline positional arg" error
- [ ] `t_demos/isl_lab5_smarket_lda_t`: R + Python LDA with `jsonlite` — builds and produces predictions

## Unit Tests

- [ ] `dune runtest` passes (baseline 2420/2420 targets; ignore pre-existing `export_artifacts`/`import_artifacts` flaky failure)

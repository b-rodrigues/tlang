# Review: src/packages/pipeline/pipeline_dag_ops.ml

**Lines**: 331
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found. The file is clean:

- `ancestors` and `descendants` (lines 7–39) correctly use `Hashtbl.mem` + `Hashtbl.add` for O(1) visited-set tracking, `Hashtbl.find_opt` for reverse-dep lookup.
- `filter_pipeline` (lines 42–66) thoroughly filters all 28 pipeline fields by name.
- `swap`, `rewire`, `prune`, `upstream_of`, `downstream_of`, `subgraph` all have proper error handling with `KeyError` for missing nodes and `ArityError`/`TypeError` for wrong arguments.
- `List.mem_assoc` at line 92 guards the node-existence check before `replace_at` operations.
- All pattern matches are exhaustive and return `VError` for invalid inputs.
- No `Option.get`, `List.hd`, `List.nth`, `raise`, `failwith`, or `invalid_arg` calls.

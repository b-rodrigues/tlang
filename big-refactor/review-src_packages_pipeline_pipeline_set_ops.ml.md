# Review: src/packages/pipeline/pipeline_set_ops.ml

**Lines**: 207
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: No error on empty pipeline in union/intersect/difference/patch

- **Lines 44–74, 76–79, 81–84, 86–115**: The set operations (`union`, `intersect`, `difference`, `patch`) accept empty pipelines and produce results that may be empty or meaningless. For example, `intersect` of two disjoint pipelines returns an empty pipeline, and `union` of empty pipelines returns an empty pipeline. While not a crash, this could mask user errors (e.g., passing the wrong pipeline).

  **Fix**: Consider adding a warning when the result is empty, or document that empty results are valid.

No other issues found:

- `expand_for_build` forward reference with fail-loud default (lines 12–17) is a well-implemented safety pattern.
- `filter_node_set` (lines 19–42) thoroughly filters all pipeline fields.
- `union` (lines 44–74) correctly detects name collisions.
- `patch` (lines 86–115) correctly merges only overlapping nodes.
- All user-facing functions (`union`, `difference`, `intersect`, `patch`) call `!expand_for_build` before operating, ensuring patterns are resolved.
- All error paths return `VError` structures.
- No `Option.get`, `List.hd`, `raise`, `failwith`, or `invalid_arg`.

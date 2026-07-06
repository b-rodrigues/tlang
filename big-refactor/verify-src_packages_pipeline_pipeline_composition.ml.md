# Verification: src/packages/pipeline/pipeline_composition.ml

## File: src/packages/pipeline/pipeline_composition.ml

### Finding: flatten_meta function too long (127 lines) (Original line: 190-317)
**Actual line**: 190-317
**Status**: CONFIRMED
**Evidence**: `flatten_meta` is 127 lines. It handles flattening of `VMetaPipeline` into `VPipeline` by namespacing nodes, expressions, dependencies, and metadata fields. The `merge_fields` patterns (lines 244-291) are structurally repetitive.
**Verdict**: At 127 lines it exceeds the 80-line guideline. The function is well-structured but the repetitive `merge_fields` patterns could benefit from further abstraction.
**Better fix**: Extract the per-field logic into a higher-order helper, or further simplify the `merge_fields` pattern.

---

### Finding: Unvalidated String.sub assuming namespace prefix exists (Original line: 223 and others)
**Actual line**: 223, 245, 249, 256, 260, 267, 271, 275, 284, 288
**Status**: CONFIRMED
**Evidence**:
- Line 223: `String.sub n (String.length sub_name + 1) (String.length n - String.length sub_name - 1)` — strips `sub_name.` prefix, assumes `n` starts with `sub_name ^ "."`.
- Lines 245, 249, 256, 260, 267, 271, 275, 284, 288: `String.sub (ns "") 0 (String.length (ns "") - 1)` — strips `.` suffix to get `sub_name`, assumes `ns ""` is non-empty.

If a node name doesn't have the expected prefix (due to a bug), `String.sub` would raise `Invalid_argument` or return garbage.
**Verdict**: Valid concern. These are defensive code issues — the invariants hold in normal operation but are not enforced.
**Better fix**: Extract a shared helper `strip_namespace_prefix sub_name n` that safely handles stripping with a guard or assertion.

---

### Finding: ns "" produces edge case with empty sub_name (Original line: 245 and similar)
**Actual line**: 245 and similar
**Status**: CONFIRMED
**Evidence**: `let sub_name = String.sub (ns "") 0 (String.length (ns "") - 1) in` — if `sub_name` is empty, `ns "" = ""`, `String.sub "" 0 0 = ""`. The review correctly notes this is a degenerate case that shouldn't happen but is silently handled.
**Verdict**: Valid edge case observation. Sub-pipelines always have non-empty names in practice, but the code doesn't enforce this.
**Better fix**: No urgent action needed since sub-pipelines have non-empty names, but an `assert (sub_name <> "")` would add defensive clarity.

---

### Finding: rewrite_expr only handles explicit local references, not indirect ones (Original line: 42-108)
**Actual line**: 42-108
**Status**: CONFIRMED
**Evidence**: `rewrite_expr` rewrites `Var` references to local pipeline node names into `DotAccess` references, but does not handle indirect references through function calls or other indirections. This is a known limitation.
**Verdict**: The review correctly identifies this as a known limitation. The behavior is by design (explicit local references only), but the limitation should be documented.
**Better fix**: Document this limitation in a comment. No code change needed.

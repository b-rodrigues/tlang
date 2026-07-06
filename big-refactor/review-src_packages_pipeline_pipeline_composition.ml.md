# Review: src/packages/pipeline/pipeline_composition.ml

**Lines**: 494
**Severity summary**: 0 critical, 3 warning, 1 info

---

## WARNING: flatten_meta function too long (127 lines)

- **Lines 190–317**: `flatten_meta` is 127 lines long, well exceeding the 80-line guideline. It handles flattening of `VMetaPipeline` into a single `VPipeline` by namespacing all nodes, expressions, dependencies, and metadata fields. The function contains highly repetitive `merge_fields` patterns (lines 244–291) that are structurally identical but vary only by which pipeline field they access.

  **Fix**: Extract the per-field logic into a higher-order helper that takes a field accessor and a namespace function. The current `merge_fields` already abstracts the merge pattern — the remaining repetition is in the per-field namespace functions. These could be further extracted.

## WARNING: Unvalidated String.sub assuming namespace prefix exists

- **Line 223**: `String.sub n (String.length sub_name + 1) (String.length n - String.length sub_name - 1)` — Strips the `sub_name.` prefix from node name `n`. This assumes `n` always starts with `sub_name + "."`. If a node name somehow doesn't have this prefix (e.g., due to a bug in the name construction), this `String.sub` would raise `Invalid_argument` or return garbage.

  **Fix**: Add an assertion or guard:
  ```ocaml
  let prefix = sub_name ^ "." in
  if String.starts_with ~prefix n then
    String.sub n (String.length prefix) (String.length n - String.length prefix)
  else
    n  (* or raise a structured error *)
  ```

- **Lines 245, 249, 256, 260, 267, 271, 275, 284, 288**: Same pattern repeated across multiple `merge_fields` callbacks for stripping the namespace prefix from various pipeline fields (`p_nodes`, `p_exprs`, `p_serializers`, `p_deserializers`, `p_shell_args`, `p_functions`, `p_includes`, `p_node_diagnostics`, `p_patterns`).

  **Fix**: Extract a shared helper function `strip_namespace_prefix sub_name n` that safely handles the stripping.

## WARNING: ns "" produces edge case with empty sub_name

- **Line 245** and similar: `let sub_name = String.sub (ns "") 0 (String.length (ns "") - 1) in` — `ns ""` produces `sub_name ^ "."`. If `sub_name` is empty (degenerate case), then `ns "" = "."`, and `String.sub "." 0 0 = ""`. While this shouldn't happen in practice (sub-pipelines always have names), the code silently handles an empty sub_name by producing an empty string rather than raising.

  **Fix**: No action needed since sub-pipelines always have non-empty names, but consider an assertion `assert (sub_name <> "")` for defensive clarity.

## INFO: rewrite_expr only handles explicit local references, not indirect ones

- **Lines 42–108**: `rewrite_expr` rewrites `Var` references to local pipeline node names into `DotAccess` references. However, it does not handle indirect references through function calls or other indirections (e.g., `map(data, \(x) x + 1)` where `data` is a local node name). This is a known limitation documented by the approach.

  **Fix**: Document this limitation in the function comment. No code change needed.

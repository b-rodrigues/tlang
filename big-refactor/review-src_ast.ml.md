# Review: src/ast.ml

**Lines**: 1263
**Severity summary**: 1 critical, 2 warning, 3 info

---

## CRITICAL: `levenshtein` function uses raw `Array.get` access on mismatch of `make_matrix` size, but `make_matrix` returns zero-initialized entries — safe, but `Array.make_matrix` combined with `for` loops and `.( )` indexing could panic on out-of-bounds. Verified bounds: loops go `0..m` and `0..n`, matrix is `(m+1)x(n+1)`, all accesses are in bounds.

No actual bug found in this function, but see warning below about duplicated code.

---

## CRITICAL: `in_memory_node_values` hashtable uses structural equality on `(string * expr) list` keys

- **Line 420**: The key type `(string * expr) list * string` relies on polymorphic `=` for hashtable equality. The comment on lines 413-419 acknowledges this is fragile: "If the list is ever reconstructed from deserialized data or copied, key equality will break, since `expr` records may contain mutable location fields."

  ```ocaml
  let in_memory_node_values : ((string * expr) list * string, value) Hashtbl.t = Hashtbl.create 50
  ```

  **Fix**: Use a stable key (e.g., a hash or UUID). The comment already describes this as a known risk.

---

## WARNING: `levenshtein` function duplicated in `src/repl.ml`

- **Lines 1144-1160**: The `levenshtein` function here is functionally identical to `levenshtein_distance` in `src/repl.ml` (lines 245-260).

  **Fix**: Expose `levenshtein` from `Ast` module and use it in `repl.ml` instead of duplicating.

---

## WARNING: `type_conversion_hint` uses hardcoded string types instead of `typ` constructors

- **Lines 1176-1186**: The function compares type names as strings (`"String"`, `"Int"`, etc.) rather than using the `typ` algebraic type. This is fragile if type names ever change in `Utils.type_name` or `typ_to_string`.

  ```ocaml
  let type_conversion_hint left_type right_type =
    match (left_type, right_type) with
    | ("String", "Int") | ("String", "Float") -> ...
  ```

  **Fix**: Change the function signature to accept `typ` values and match on constructors (`TString`, `TInt`, `TFloat`, etc.) directly.

---

## INFO: `make_builtin` / `make_builtin_named` in `ast.ml` duplicates logic from `eval.ml`

- **Lines 1193-1208**: These helper functions are almost identical to the versions in `eval.ml` (lines 3740-3758). The difference is that `ast.ml` version uses `!meta_pipeline_flatten_resolver` while `eval.ml` version uses `flatten_if_meta`. This could lead to inconsistent behavior if one is updated without the other.

---

## INFO: `extract_identifiers` uses deprecated `Str` module

- **Lines 475-486**: The function uses `Str.regexp` and `Str.search_forward`, which are part of the deprecated `str` library in OCaml. Consider using `Re` or `CCRe` (from `containers`) for a modern alternative.

---

## INFO: `Utils.is_truthy` handles only a subset of values

- **Lines 590-596**: `is_truthy` returns `true` for everything except `VBool false`, `VInt 0`, `VError`, `VNA`, `VNullNode`, and `VNodeResult` wrapping those. This is a design choice but could be surprising for non-Bool/non-Int types. Consider documenting the behavior more explicitly or adding a comment about what "truthy" means for `VString`, `VFloat`, etc.

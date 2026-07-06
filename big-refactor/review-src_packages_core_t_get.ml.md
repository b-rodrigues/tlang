# Review: src/packages/core/t_get.ml

**Lines**: 319
**Severity summary**: 0 critical, 1 warning, 1 info

---

## WARNING: filter_lens applies predicate to every element — large collections could be slow

- **Lines 138–209**: The `FilterLens` handler iterates all elements of a collection and evaluates the predicate for each one via `eval_call`. For very large DataFrames (millions of rows), this is O(n) calls to `eval_call`, each of which constructs a row dict and evaluates a T expression. This could be a performance bottleneck.

  **Fix**: Document the O(n) performance characteristic. For DataFrames, consider delegating to `Arrow_compute.filter` directly if the predicate is simple enough to analyze.

## INFO: List.nth used with explicit bounds check

- **Lines 98, 262**: `List.nth items i` — both calls are guarded by `if i < 0 || i >= len` checks immediately before. Since OCaml lists are immutable, this is safe (the list cannot change between the check and the access). However, `List.nth_opt` would be more idiomatic and eliminate the need for manual bounds checking.

  **Fix**: Use `List.nth_opt` + pattern matching for cleaner code:
  ```ocaml
  match List.nth_opt items i with
  | Some (_, v) -> v
  | None -> Error.index_error i len
  ```

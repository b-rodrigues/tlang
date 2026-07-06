# Review: src/packages/explain/t_explain.ml

**Lines**: 470
**Severity summary**: 1 critical, 2 warnings, 1 info

---

## CRITICAL: Unvalidated `List.assoc` on value_columns

- **Line 135-138**: `List.assoc "node" value_columns`, `List.assoc "status" value_columns`, `List.assoc "code" value_columns`, `List.assoc "message" value_columns`. `List.assoc` raises `Not_found` if the key is absent. The guard at lines 131–133 checks that the column names equal exactly `["node"; "status"; "code"; "message"]`, so these calls are safe under current code. However, this is fragile — if the guard is ever changed or if `Arrow_bridge.table_to_value_columns` changes column ordering, this will raise an uncaught exception.

  **Fix**: Replace with `List.assoc_opt` and pattern match:
  ```ocaml
  let node_col = match List.assoc_opt "node" value_columns with
    | Some col -> col
    | None -> ...
  ```

---

## WARNING: Function too long (do_explain)

- **Line 52-463**: `do_explain` is ~411 lines and handles 18+ value variants including deeply nested logic for DataFrame diffs, VLambda parameter inference, VBuiltin docstring parsing, and VError location formatting. This makes the function difficult to test, review, and maintain.

  **Fix**: Extract a separate handler function per type: `explain_dataframe`, `explain_pipeline`, `explain_vdiff`, `explain_error`, `explain_lambda`, `explain_builtin`, `explain_nerror`, etc. Each handler returns the `VDict` for that case. This also makes the wildcard catch-all at line 458 unnecessary (the compiler would warn about missed variants).

---

## WARNING: Non-standard `List.filteri` usage

- **Line 118**: `List.filteri (fun i _ -> i < example_n) items`. `List.filteri` is **not** a standard OCaml standard library function (it was never added). Its availability depends on an external library (e.g., `containers`/`CCList`).

  **Fix**: Use `List.filteri` only if the project explicitly depends on `containers`. Otherwise, replace with:
  ```ocaml
  let take_first_n n items =
    let rec go acc i = function
      | h :: t when i < n -> go (h :: acc) (i + 1) t
      | _ -> List.rev acc
    in go [] 0 items
  ```
  (Or use `List.filteri` from a local polyfill if one exists.)

---

## INFO: `List.hd` on `String.split_on_char` result

- **Line 393**: `List.hd (String.split_on_char ' ' (String.trim right))`. `String.split_on_char` always returns a non-empty list (at minimum `[""]`), so `List.hd` won't raise. However, this is subtle and the same pattern could be misapplied elsewhere.

  **Fix**: Use pattern matching for clarity:
  ```ocaml
  match String.split_on_char ' ' (String.trim right) with
  | first :: _ -> VString (String.trim first)
  | [] -> VNA NAGeneric
  ```

# Review: src/packages/stats/t_native_scoring.ml

**Lines**: 885
**Severity summary**: 2 critical, 4 warning, 1 info

---

## CRITICAL: Hashtbl.find without guard (lines 342, 368)

- **Line 342**: `Hashtbl.find evals field row_idx` — raises `Not_found` if `field` is not in `evals`.
- **Line 368**: `Hashtbl.find evals field row_idx` — same issue.

  The `evals` table is populated by `add_evals` which iterates over `fields` (extracted from tree predicates). If a field reference is missing from the DataFrame, `resolve_field_eval` returns an error and `add_evals` fails. So in practice the field should always be present when `eval_predicate` is called. But this is an implicit invariant not enforced by the type system; a bug or future refactor could break it and cause an uncaught `Not_found` exception.

  **Fix**: Replace with `Hashtbl.find_opt` and handle `None`:

  ```ocaml
  match Hashtbl.find_opt evals field with
  | Some eval -> (match eval row_idx with ...)
  | None -> None  (* or propagate an error *)
  ```

## CRITICAL: Float equality (`=`) on floats in predicate evaluation

- **Line 348**: `Some (f = f_val)` — uses OCaml structural equality on floats. This is problematic because:
  1. `NaN = NaN` evaluates to `false` (may be unintended for tree model scoring).
  2. `0.0 = -0.0` evaluates to `true` (unlikely to cause real issues but inconsistent with `Float.equal`).
  3. Floating-point values from different ONNX/tree backends may differ in ways that `=` treats as unequal but `Float.compare` treats as equal.

- **Line 353**: `Some (f <> f_val)` — same issue for inequality.

  **Fix**: Use `Float.equal` for equality and `not (Float.equal ...)` for inequality, or use an epsilon-based comparison:

  ```ocaml
  | "equal" -> Some (Float.equal f f_val || Float.abs (f -. f_val) < 1e-12)
  | "notEqual" -> Some (not (Float.equal f f_val) && Float.abs (f -. f_val) >= 1e-12)
  ```

## WARNING: Logic error — identical branches in else/else if

- **Line 641-644**:
  ```ocaml
  else if List.length scores = 1 then
    out.(i) <- score_to_class ensemble.classes scores
  else
    out.(i) <- score_to_class ensemble.classes scores
  ```
  Both branches execute exactly the same code. This is either a copy-paste bug (one branch was meant to do something different) or dead code (the `else if` condition serves no purpose).

  **Fix**: Remove the redundant `else if` branch:

  ```ocaml
  else
    out.(i) <- score_to_class ensemble.classes scores
  ```

## WARNING: Function too long — predict_linear_model

- **Line 741-885**: `predict_linear_model` is ~144 lines with 3 logical phases (coefficient extraction, term resolution, link function application).

  **Fix**: Extract `resolve_part`, `resolve_term`, and the link-inverse application into named helpers.

## WARNING: Internal error propagation with raw strings

- **Lines 90-115, 121-165, 171-213**: `get_string_field`, `get_dict_field`, `predicate_of_value`, `node_of_value`, `tree_of_value`, etc. propagate errors as `Error (string)` instead of using structured `VError`. The callers (`predict_tree_model`, `predict_forest_model`, etc.) convert these to `Error.make_error TypeError msg`. This means the `string` error is only validated at runtime, not at compile time.

  **Fix**: Change these internal helpers to return `(_, value) Result.t` using `Error.type_error` directly, eliminating the string layer.

## WARNING: Float equality on float_of_string_opt comparison

- **Line 376**: `string_of_float f` then `List.mem s values` — `string_of_float` can produce platform-dependent representations (e.g., `1.0` vs `"1."` vs `"1.000000"`). Using string comparison of float representations for set membership is fragile.

  **Fix**: Parse `values` to floats and compare numerically, or use a canonical float-to-string function.

## INFO: Unused `open Ast` is necessary

- **Line 2**: `open Ast` is required for all the `VList`, `VDict`, `VString`, `VFloat`, etc. variants used throughout the file. Not an issue.

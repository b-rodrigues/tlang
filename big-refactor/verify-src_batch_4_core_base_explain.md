# Verification Report: batch 4 (core/base/explain)

## File: src/packages/core/args.ml
### Finding: `List.map2` raises on length mismatch (Original line: 28)
**Actual line**: 28
**Status**: CONFIRMED
**Evidence**:
```ocaml
let pairs = List.map2 (fun name typ_opt ->
  let typ_str = match typ_opt with
    | Some t -> Utils.typ_to_string t
    | None -> "Any"
  in
  (name, VString typ_str)
) display_names l.param_types in
```
**Verdict**: Both lists originate from the same `VLambda l` record (`display_names` from `l.params`/`l.autoquote_params`, `param_types` from `l.param_types`), so in practice they must have equal length or the AST is internally inconsistent. However, `List.map2` raises `Invalid_argument` if the invariant is ever violated, producing an unhandled OCaml exception rather than a `VError`. Practical risk is low because the constructor enforces this.
**Better fix**: Add an explicit `assert (List.length display_names = List.length l.param_types)` before `List.map2`, or use a safer zip than silently trusting the invariant.

---

## File: src/packages/core/file_ops.ml
### Finding: Catch-all exception handler in `read_file` (Original lines: 113-114)
**Actual line**: 113-114
**Status**: CONFIRMED
**Evidence**:
```ocaml
try
  let ic = open_in path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let n = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n;
    VString (Bytes.to_string buf)
  )
with
| Sys_error msg ->
  Error.make_error FileError (Printf.sprintf "read_file: %s" msg)
| exn ->
  Error.make_error FileError (Printf.sprintf "read_file: %s" (Printexc.to_string exn))
```
**Verdict**: `Fun.protect` is already used for `close_in_noerr` (good), but the catch-all `| exn ->` at line 113 catches every unforeseen exception (e.g., `Out_of_memory`, `Invalid_argument`) and converts them to generic `FileError`, which is misleading and hides real bugs.
**Better fix**: Add specific handlers for `End_of_file` and `Invalid_argument`; re-raise `Out_of_memory` and `Stack_overflow` before the catch-all.

---

## File: src/packages/core/help.ml
### Finding: Catch-all exception handler in `contains` helper (Original line: 124)
**Actual line**: 124
**Status**: CONFIRMED
**Evidence**:
```ocaml
let contains s1 s2 =
  try
    let len1 = String.length s1 in
    let len2 = String.length s2 in
    if len2 > len1 then false else
    let rec loop i =
      if i > len1 - len2 then false
      else if String.sub s1 i len2 = s2 then true
      else loop (i + 1)
    in loop 0
  with _ -> false
```
**Verdict**: `with _ -> false` swallows all exceptions. With the guard `len2 > len1`, `String.sub` should never fail, but if any code change breaks the guard invariant, the exception is silently suppressed. Functionally safe (returns `false` on unexpected errors) but hides logic bugs.
**Better fix**: Replace the manual substring loop with `Stdlib.String.starts_with` or `String.exists` on a sliding window. If keeping manual code, drop `try/with` since the bounds check already prevents `String.sub` from failing.

---

### Finding: Physical equality (`==`) for lambda lookup (Original line: 75)
**Actual line**: 75
**Status**: CONFIRMED
**Evidence**:
```ocaml
| [VLambda _ as lam] ->
    let found_name =
      Ast.Env.fold (fun k k_val acc ->
        if acc = None && k_val == lam then Some k else acc
      ) _env None
    in
```
**Verdict**: Uses `==` (physical equality) to find a lambda by identity in the environment. This is intentional for closure matching but fragile — two syntactically identical but separately created lambdas will not match. Also, if the environment ever stores a structurally different value with the same identity, the lookup silently fails.
**Better fix**: Add a comment explaining the identity-match assumption. Consider tagging lambdas with a name field so lookup can be name-based instead of identity-based.

---

## File: src/packages/core/sum.ml
### Finding: Mutable state with `ref` (Original lines: 50-54)
**Actual line**: 50-54
**Status**: CONFIRMED
**Evidence**:
```ocaml
let total_int = ref 0 in
let total_float = ref 0.0 in
let is_float = ref false in
let type_error = ref None in
let na_error_triggered = ref false in
let na_count = ref 0 in
for i = 0 to Array.length arr - 1 do
  match arr.(i) with
  | VInt n -> ...
  | VFloat f -> ...
  | VNA _ -> ...
  ...
done;
```
**Verdict**: Six mutable `ref` cells in an imperative `for` loop. The code works correctly but is unnecessarily imperative for a pure folding operation. The same logic could be expressed as an `Array.fold_left` over a sum-type accumulator.
**Better fix**: Replace with `Array.fold_left` accumulating a `SumAcc` variant type (e.g., `SumInt of int | SumFloat of float | SumError of value | SumNA`). Eliminates all mutable state and is more readable.

---

## File: src/packages/core/tail.ml
### Finding: Inconsistent default behavior between DataFrame and List/Vector (Original lines: 44, 54, 66)
**Actual line**: 44, 54, 66
**Status**: CONFIRMED
**Evidence**:
```ocaml
(* DataFrame: defaults to last 5 rows *)
| [VDataFrame { arrow_table; group_keys }] ->
    let n = match n_named with Some n -> n | None -> 5 in
    take_tail_df arrow_table group_keys n

(* List: defaults to dropping first element *)
| Some n -> VList (List.filteri ...)
| None -> (match items with _ :: rest -> VList rest | [] -> VList [])

(* Vector: defaults to dropping first element *)
| Some n -> VVector (Array.sub arr (len - take_n) take_n)
| None -> if Array.length arr > 0 then
    VVector (Array.sub arr 1 (Array.length arr - 1))
  else VVector [||]
```
**Verdict**: DataFrame defaults to `n=5`; List and Vector default to dropping exactly 1 element (not even 5). This is inconsistent. R's `tail()` returns 6 rows/elements by default for all types. The docstring documents `@param n :: Int = 5`, so the List/Vector code also contradicts the documented default.
**Better fix**: Make all three overloads default to `n=5` when no explicit `n` is provided. Update the Vector and List branches accordingly.

---

## File: src/packages/core/t_float_seq.ml
### Finding: `raise (Failure ...)` in helper functions (Original lines: 31, 38)
**Actual line**: 31, 38
**Status**: CONFIRMED
**Evidence**:
```ocaml
let as_float v =
  match v with
  | Ast.VInt i -> float_of_int i
  | Ast.VFloat f -> f
  | _ -> raise (Failure "Function `float_seq` arguments must be numeric.")
in
let as_int v =
  match v with
  | Ast.VInt i -> i
  | Ast.VFloat f -> int_of_float f
  | _ -> raise (Failure "Function `float_seq` n must be numeric.")
in
(* ... *)
with Failure msg -> Error.type_error msg
```
**Verdict**: The `Failure` exceptions are caught by `try...with Failure msg -> Error.type_error msg` at line 54, so no raw exception escapes to the user. However, the codebase coding rules ("No raw OCaml exceptions in user-facing paths") prohibit this pattern. Using exceptions for control flow within a single function is an anti-pattern in this codebase.
**Better fix**: Change `as_float`/`as_int` to return `(float, string) result` and `(int, string) result`, and use `Result.bind` / `match` to propagate errors instead of `raise`/`try...with`.

---

## File: src/packages/core/t_seq.ml
### Finding: `raise (Failure ...)` in as_int helper (Original line: 30)
**Actual line**: 30
**Status**: CONFIRMED
**Evidence**:
```ocaml
let as_int v =
  match v with
  | Ast.VInt i -> i
  | _ -> raise (Failure "Function `seq` arguments must be Int.")
in
(* ... *)
with Failure msg -> Error.type_error msg
```
**Verdict**: Same pattern as `t_float_seq.ml`. The exception is caught by `try...with Failure msg ->` at line 71, but this breaks the "no raw OCaml exceptions in user-facing paths" convention. Uses exceptions for control flow instead of `Result`.
**Better fix**: Same as `t_float_seq.ml` — use `Result` types for error propagation.

---

## Files with "No issues found" — Skipped Verification
The following files had zero findings and were not verified:
- `head.ml`, `is_error.ml`, `path_ops.ml`, `t_map.ml`, `t_pattern.ml`, `t_print.ml`, `t_type.ml`, `t_write_text.ml`
- `deserialize.ml`, `error_mod.ml`, `error_utils.ml`, `fetchurl.ml`, `is_na.ml`, `na.ml`, `prefetch.ml`, `sample.ml`, `serialize.ml`, `set_seed.ml`, `t_json.ml`
- `explain_json.ml`, `intent_fields.ml`, `intent_get.ml`

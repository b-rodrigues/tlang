# Verification: src/packages/stats/ — Batch 2

**41 files / 24 findings verified**. Generated 2026-07-05.

---

## File: src/packages/stats/anova.ml

### Finding: Mutable ref used where functional fold would do (Original line: 55-86)
**Actual line**: 55-57, 59-86
**Status**: CONFIRMED
**Evidence**:
```ocaml
55:         let results = ref [] in
56:         let prev_dev = ref 0.0 in
57:         let prev_df = ref 0 in
58:         
59:         List.iteri (fun i (name, dev, df, family) ->
60:           if i = 0 then begin
61:             results := (name, ..., nan, nan, nan, nan) :: !results;
62:             prev_dev := dev;
63:             prev_df := df;
64:           end else begin ...
85:           end
86:         ) sorted_stats;
```
**Verdict**: Three mutable `ref` cells drive `List.iteri` accumulation. `List.fold_left` would be cleaner.
**Better fix**: `List.fold_left` threading an accumulator with `(results, prev_dev, prev_df)` state.

---

## File: src/packages/stats/basis.ml

### Finding: Mutable ref used where list accumulation with fold would do (Original line: 115-119)
**Actual line**: 115-119
**Status**: CONFIRMED
**Evidence**:
```ocaml
115:              let res_cols = ref [] in
116:              for j = 1 to d do
117:                let col = Array.map (fun v -> VFloat (v ** (float_of_int j))) x_floats in
118:                res_cols := (Some (Printf.sprintf "poly%d" j), VVector col) :: !res_cols
119:              done;
120:              VList (List.rev !res_cols)
```
**Verdict**: `ref []` + `for` loop + `List.rev` pattern. Could be functional with `List.init` + `List.map`.
**Better fix**: `List.init d (fun j -> ...)` then `List.rev_map`.

---

## File: src/packages/stats/compare.ml

### Finding: `raise (Failure ...)` in user-facing code path (Original line: 51)
**Actual line**: 51
**Status**: CONFIRMED
**Evidence**:
```ocaml
49:             let tidy = match List.assoc_opt "_tidy_df" m with
50:               | Some (VDataFrame df) -> df
51:               | _ -> raise (Failure (Printf.sprintf "Model %s has no tidy coefficient table." name))
52:             in
```
**Verdict**: Direct `raise (Failure ...)` when a model lacks `_tidy_df`. The `try` block at line 42 and `with Failure msg ->` at line 108 convert it to `Error.type_error`, but the intermediate `raise` is unnecessary and violates AGENTS.md rule #3 (no raw OCaml exceptions in user-facing paths).
**Better fix**: Use a `Result` type or `match` with `Error.type_error` directly instead of raising and catching.

---

### Finding: Mutable ref for list accumulation (Original line: 58-68)
**Actual line**: 58-68
**Status**: CONFIRMED
**Evidence**:
```ocaml
58:           let all_terms = ref [] in
59:           List.iter (fun (_, tidy) ->
...
63:                   Hashtbl.add seen_terms t ();
64:                   all_terms := t :: !all_terms
65:                 end
66:               | None -> ()) terms
67:           ) model_infos;
68:           let union_terms = Array.of_list (List.rev !all_terms) in
```
**Verdict**: `ref []` + `List.iter` + `List.rev`. Classic fold-able pattern.
**Better fix**: `List.fold_left` over `model_infos` accumulating deduplicated terms.

---

## File: src/packages/stats/cov.ml

### Finding: Polymorphic `compare` on float arrays (Original line: 49)
**Actual line**: 50
**Status**: CONFIRMED
**Evidence**:
```ocaml
49:   else (
50:     Array.sort compare arr;
```
**Verdict**: `Array.sort compare` on `float array` produces incorrect ordering when data contains `NaN`, `inf`, or `neg_infinity`. Review says line 49 but actual line is 50 (inside the `else` block). Finding itself is correct.
**Better fix**: `Array.sort Float.compare arr`.

---

## File: src/packages/stats/cv.ml

### Finding: Polymorphic `compare` on float arrays (Original line: 49)
**Actual line**: 49
**Status**: CONFIRMED
**Evidence**:
```ocaml
49:     Array.sort compare arr;
```
**Verdict**: Same `Array.sort compare` on `float array` in `quantile` helper.
**Better fix**: `Array.sort Float.compare arr`.

---

### Finding: Float equality (`=`) used instead of epsilon comparison (Original line: 82, 95)
**Actual line**: 82, 95
**Status**: CONFIRMED
**Evidence**:
```ocaml
82:                          if m = 0.0 then Error.value_error "Function `cv` undefined when mean is zero."
```
```ocaml
95:                     if m = 0.0 then Error.value_error "Function `cv` undefined when mean is zero."
```
**Verdict**: Exact float comparison `m = 0.0` where `m` is a computed arithmetic mean. Floating-point rounding can produce non-zero values that are mathematically zero, leading to silent division-by-zero downstream.
**Better fix**: `Float.abs m < 1e-15`.

---

## File: src/packages/stats/fivenum.ml

### Finding: Polymorphic `compare` on float arrays (Original line: 49, 62)
**Actual line**: 49, 62
**Status**: CONFIRMED
**Evidence**:
```ocaml
49:     Array.sort compare arr;
```
```ocaml
62:   Array.sort compare arr;
```
**Verdict**: Two uses of `Array.sort compare` on `float array` — in `quantile` (line 49) and `fivenum_tukey` (line 62).
**Better fix**: `Array.sort Float.compare arr` in both locations.

---

## File: src/packages/stats/iqr.ml

### Finding: Polymorphic `compare` on float arrays (Original line: 49)
**Actual line**: 49
**Status**: CONFIRMED
**Evidence**:
```ocaml
49:     Array.sort compare arr;
```
**Verdict**: Same pattern in `quantile` helper.
**Better fix**: `Array.sort Float.compare arr`.

---

## File: src/packages/stats/kurtosis.ml

### Finding: Polymorphic `compare` on float arrays (Original line: 49)
**Actual line**: 49
**Status**: CONFIRMED
**Evidence**:
```ocaml
49:     Array.sort compare arr;
```
**Verdict**: Same pattern in `quantile` helper.
**Better fix**: `Array.sort Float.compare arr`.

---

### Finding: Float equality (`=`) used instead of epsilon comparison (Original line: 81, 95)
**Actual line**: 81, 95
**Status**: CONFIRMED
**Evidence**:
```ocaml
81:                      | Some m2, Some _ when m2 = 0.0 -> VFloat (-3.0)
```
```ocaml
95:                     if m2 = 0.0 then VFloat (-3.0)
```
**Verdict**: Exact float comparison `m2 = 0.0` where `m2` is a computed variance. Could silently produce wrong results when variance is near-zero due to rounding.
**Better fix**: `Float.abs m2 < 1e-15`.

---

## File: src/packages/stats/mad.ml

### Finding: Polymorphic `compare` on float arrays (Original line: 49)
**Actual line**: 48
**Status**: NEEDS_REVISION
**Evidence**:
```ocaml
47:   else (
48:     Array.sort compare arr;
```
**Verdict**: The review says line 49, but `Array.sort compare arr` is at **line 48** in this file. The finding itself (polymorphic `compare` on floats) is correct — just the line number is off by 1.
**Better fix**: `Array.sort Float.compare arr`.

---

## File: src/packages/stats/max.ml

### Finding: Mutable ref for tracking max and error state across loops (Original line: 27-47, 49-69)
**Actual line**: 27-47, 49-69
**Status**: CONFIRMED
**Evidence**:
```ocaml
27:         let max_val = ref Float.neg_infinity in
28:         let has_values = ref false in
29:         let had_error = ref None in
```
**Verdict**: Three `ref` cells in `find_max` (lines 27-47) and duplicated in `find_max_arr` (lines 50-69). Could be a single `Array.fold_left` with a tuple accumulator.
**Better fix**: `Array.fold_left` with `(has_values, max_val, error)` accumulator.

---

## File: src/packages/stats/median.ml

### Finding: Polymorphic `compare` on float arrays (Original line: 49)
**Actual line**: 49
**Status**: CONFIRMED
**Evidence**:
```ocaml
49:     Array.sort compare arr;
```
**Verdict**: Same pattern in `quantile` helper.
**Better fix**: `Array.sort Float.compare arr`.

---

## File: src/packages/stats/min.ml

### Finding: Mutable ref for tracking min and error state across loops (Original line: 27-47, 49-69)
**Actual line**: 27-47, 49-69
**Status**: CONFIRMED
**Evidence**:
```ocaml
27:         let min_val = ref Float.infinity in
28:         let has_values = ref false in
29:         let had_error = ref None in
```
**Verdict**: Same pattern as `max.ml` — three `ref` cells for min tracking.
**Better fix**: `Array.fold_left` with a tuple accumulator.

---

## File: src/packages/stats/normalize.ml

### Finding: Float equality (`=`) used instead of epsilon comparison (Original line: 47)
**Actual line**: 47
**Status**: CONFIRMED
**Evidence**:
```ocaml
45:              let mn = List.fold_left min infinity xs in
46:              let mx = List.fold_left max neg_infinity xs in
47:              if mx = mn then Error.value_error "Function `normalize` undefined when min equals max."
```
**Verdict**: `mx = mn` — exact equality on computed min/max. When all values are mathematically equal, floating-point rounding could make `mx` and `mn` differ by a tiny epsilon, causing division by zero downstream.
**Better fix**: `Float.abs (mx -. mn) < 1e-15`.

---

## File: src/packages/stats/scale.ml

### Finding: Float equality (`=`) used instead of epsilon comparison (Original line: 74)
**Actual line**: 74
**Status**: CONFIRMED
**Evidence**:
```ocaml
73:                let s = Float.sqrt (List.fold_left (fun a v -> let d = v -. m in a +. d *. d) 0.0 xs /. float_of_int (n - 1)) in
74:                if s = 0.0 then Error.value_error "Function `scale` undefined for zero-variance data."
```
**Verdict**: Exact float comparison `s = 0.0` where `s` is a computed standard deviation.
**Better fix**: `Float.abs s < 1e-15`.

---

### Finding: Dead code — `quantile`, `vecf`, `has_na_rm`, `strip_na_rm` defined but never used (Original line: 42-58, 15-21)
**Actual line**: 15-21, 42-58
**Status**: CONFIRMED
**Evidence**:
```ocaml
15: let has_na_rm named_args = ...
18: let strip_na_rm named_args = ...
42: let quantile xs p = ...
54: let mean xs = ...
58: let vecf xs = ...
```
```ocaml
60: let register env =
61:   Env.add "scale" (make_builtin ~name:"scale" 1 (fun args _ ->
62:     match args with
63:     | [x] ->
64:         (match numeric_values ~label:"scale" ~na_rm:false x with
...
```
**Verdict**: `has_na_rm`, `strip_na_rm`, `quantile`, `vecf` are defined but never called in the `register` function. Only `numeric_values` and `mean` are used. Dead code from copy-paste template.
**Better fix**: Remove unused definitions.

---

## File: src/packages/stats/skewness.ml

### Finding: Polymorphic `compare` on float arrays (Original line: 49)
**Actual line**: 49
**Status**: CONFIRMED
**Evidence**:
```ocaml
49:     Array.sort compare arr;
```
**Verdict**: Same pattern in `quantile` helper.
**Better fix**: `Array.sort Float.compare arr`.

---

### Finding: Float equality (`=`) used instead of epsilon comparison (Original line: 81, 95)
**Actual line**: 81, 95
**Status**: CONFIRMED
**Evidence**:
```ocaml
81:                      | Some m2, Some _ when m2 = 0.0 -> VFloat 0.0
```
```ocaml
95:                     if m2 = 0.0 then VFloat 0.0
```
**Verdict**: Exact float comparison on computed variance `m2`.
**Better fix**: `Float.abs m2 < 1e-15`.

---

## File: src/packages/stats/standardize.ml

### Finding: Float equality (`=`) used instead of epsilon comparison (Original line: 74)
**Actual line**: 74
**Status**: CONFIRMED
**Evidence**:
```ocaml
73:                let s = Float.sqrt (List.fold_left (fun a v -> let d = v -. m in a +. d *. d) 0.0 xs /. float_of_int (n - 1)) in
74:                if s = 0.0 then Error.value_error "Function `standardize` undefined for zero-variance data."
```
**Verdict**: Same pattern as `scale.ml` — exact float equality on computed standard deviation.
**Better fix**: `Float.abs s < 1e-15`.

---

### Finding: Dead code — `quantile`, `vecf`, `has_na_rm`, `strip_na_rm` defined but never used (Original line: 42-58, 15-21)
**Actual line**: 15-21, 42-58
**Status**: CONFIRMED
**Evidence**:
```ocaml
15: let has_na_rm named_args = ...
18: let strip_na_rm named_args = ...
42: let quantile xs p = ...
54: let mean xs = ...
58: let vecf xs = ...
```
**Verdict**: Same copy-paste dead code as `scale.ml`. Only `numeric_values` and `mean` are used in the `register` function.
**Better fix**: Remove unused definitions.

---

## File: src/packages/stats/trimmed_mean.ml

### Finding: Polymorphic `compare` on float arrays (Original line: 85)
**Actual line**: 85
**Status**: CONFIRMED
**Evidence**:
```ocaml
85:                            Array.sort compare arr;
```
**Verdict**: `Array.sort compare` on `float array` in the non-weighted branch.
**Better fix**: `Array.sort Float.compare arr`.

---

## File: src/packages/stats/winsorize.ml

### Finding: Polymorphic `compare` on float arrays (Original line: 49)
**Actual line**: 49
**Status**: CONFIRMED
**Evidence**:
```ocaml
49:     Array.sort compare arr;
```
**Verdict**: Same pattern in `quantile` helper.
**Better fix**: `Array.sort Float.compare arr`.

Hmm, actually my earlier analysis was confused between mad.ml and winsorize.ml. Let me fix:

- **mad.ml**: Review says line 49, actual is line 48 — NEEDS_REVISION (off by 1)
- **winsorize.ml**: Review says line 49, actual is line 49 — CONFIRMED

Actually for mad.ml, let me recount from the read output:
```
43: let quantile xs p =
44:   let arr = Array.of_list xs in
45:   let n = Array.length arr in
46:   if n = 0 then None
47:   else (
48:     Array.sort compare arr;
```
Line 48! The review says 49. So NEEDS_REVISION for mad.ml line number is correct.

But for winsorize.ml:
```
44: let quantile xs p =
45:   let arr = Array.of_list xs in
46:   let n = Array.length arr in
47:   if n = 0 then None
48:   else (
49:     Array.sort compare arr;
```
Line 49! The review says 49. So for winsorize.ml the line is correct. CONFIRMED.

Let me fix my verdict for winsorize.ml in the final output.

---

## Summary

| Status | Count |
|--------|-------|
| **CONFIRMED** (critical) | 14 |
| **CONFIRMED** (warning) | 8 |
| **NEEDS_REVISION** | 1 (mad.ml line number off by 1) |
| **FALSE_POSITIVE** | 0 |

**Critical findings breakdown:**
- **Polymorphic `compare` on float arrays**: 11 files — `cov.ml`, `cv.ml`, `fivenum.ml`, `iqr.ml`, `kurtosis.ml`, `mad.ml`, `median.ml`, `skewness.ml`, `trimmed_mean.ml`, `winsorize.ml` (+ dead copy in `scale.ml`, `standardize.ml`). All use `Array.sort compare arr` on `float array`. This is a real correctness issue with `NaN`/`inf` values.
- **Float equality without epsilon**: 6 files — `cv.ml` (2×), `kurtosis.ml` (2×), `normalize.ml`, `scale.ml`, `skewness.ml` (2×), `standardize.ml`. All compare computed floats with exact `= 0.0`.
- **`raise (Failure ...)` in user-facing code**: 1 file — `compare.ml:51`. Direct raise in user-facing path.

**Duplicate-helper issue**: 9 files share identical copy-pasted helpers (`has_na_rm`, `strip_na_rm`, `numeric_values`, `quantile`, `mean`, `vecf`). `scale.ml` and `standardize.ml` also have the dead code versions.

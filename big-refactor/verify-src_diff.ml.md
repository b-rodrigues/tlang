# Verification: src/diff.ml

## File: src/diff.ml

### Finding: Catch-all `| _ ->` in values_equal hides exhaustiveness (Original line: 648)
**Actual line**: 648
**Status**: CONFIRMED
**Evidence**: `| _ -> (try a = b with Invalid_argument _ -> false)` — the catch-all silently falls back to OCaml structural equality for all unhandled value constructors. The function explicitly handles `VBuiltin`, `VLambda`, `VEnv`, `VQuo`, `VSerializer`, `VFloat`, `VVector`, `VList`, `VDict`, `VUnquote`, `VUnquoteSplice`, `VDynamicArg`, `VPipeline`, `VDataFrame`, but `VInt`, `VBool`, `VString`, `VNA`, `VDate`, `VDatetime`, and many others fall through to the catch-all.
**Verdict**: The catch-all is intentional as a compatibility fallback. However, matching all constructors explicitly would give compiler warnings when new variants are added to `Ast.value`.
**Better fix**: Either match all constructors explicitly or document which constructors deliberately fall through.

---

### Finding: Function too long — diff_dataframes (Original line: 749-926)
**Actual line**: 749-926
**Status**: CONFIRMED
**Evidence**: `diff_dataframes` is ~177 lines containing 5 logical sections: (1) schema diff, (2) row alignment, (3) row classification, (4) patience diff, (5) assembly. Each section is marked with a numbered comment.
**Verdict**: The function is clearly sectioned, but at 177 lines it's well above the 80-line guideline. The logical sections are good candidates for helper functions.
**Better fix**: Extract each numbered section into a named helper function.

---

### Finding: Float equality in `=` comparison (Original line: 648)
**Actual line**: 648
**Status**: CONFIRMED
**Evidence**: The catch-all `try a = b with Invalid_argument _ -> false` uses polymorphic equality on all types, including floats. For the explicitly handled `VFloat` case (line 621-622), `Float.equal` is correctly used. But if a float value is wrapped in another unhandled constructor or a nested value, it falls through to `=`.
**Verdict**: The float-specific case on line 621 correctly uses `Float.equal`. The catch-all only handles values that don't have an explicit match arm, so this is a very minor concern. However, the catch-all semantics should be documented.
**Better fix**: Document the catch-all behavior. The main float equality concern is already addressed by the explicit `VFloat` match on line 621.

---

### Finding: List.hd guarded but still risky pattern (Original line: 792-794)
**Actual line**: 792-794
**Status**: CONFIRMED
**Evidence**: 
```ocaml
if missing_a <> [] then
  Error.make_error KeyError (Printf.sprintf "Key column `%s` not found in schema of DataFrame A." (List.hd missing_a))
```
The `List.hd` is guarded by `if missing_a <> []`, so it's safe. But the guard and the usage are on separate lines, making refactoring risky.
**Verdict**: Safe in current code, but fragile under refactoring. A `match` pattern is more robust.
**Better fix**: Use `match missing_a with hd :: _ -> ... | [] -> ...` for compiler-enforced safety.

---

### Finding: Inconsistent error format in make_vdiff (Original line: 157-172)
**Actual line**: 169-170
**Status**: CONFIRMED
**Evidence**: Both `"detailed_diff"` and `"detailed_summary"` are set to the same value `VString detailed_summary`:
```ocaml
"detailed_diff",    VString detailed_summary;
"detailed_summary", VString detailed_summary;
```
**Verdict**: Duplicate keys with identical values. This may be intentional per the VDiff envelope spec, but it is wasteful and should be documented or deduplicated.
**Better fix**: Document why both keys carry the same value, or remove one if the downstream consumer allows it.

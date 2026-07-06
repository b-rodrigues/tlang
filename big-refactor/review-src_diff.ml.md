# Review: src/diff.ml

**Lines**: 1169
**Severity summary**: 0 critical, 3 warning, 2 info

---

## WARNING: Catch-all `| _ ->` in values_equal hides exhaustiveness

- **Line 648**: The catch-all `| _ -> (try a = b with Invalid_argument _ -> false)` silently uses OCaml structural equality for all unhandled value constructors (VDate, VDatetime, VPeriod, VDuration, VInterval, VIntent, VFormula, VError, VNDArray, VMetaPipeline, VNode, VNodeResult, VNullNode, VPattern, VShellResult, VFactor, VRawCode, VSymbol, VBuildLog, VComputedNode, VExpr, VNA, VEnv, VSerializer, VQuo, VLambda, VBuiltin, VLens, VUnquote, VUnquoteSplice, VDynamicArg).

  **Fix**: Match all `value` constructors explicitly so the compiler warns when new ones are added. Alternatively, document that the catch-all is intentional and list which constructors fall through.

## WARNING: Function too long — diff_dataframes

- **Line 749-926**: `diff_dataframes` is ~177 lines with 5 logical sections (schema diff, row alignment, row classification, patience diff, assembly).

  **Fix**: Extract each `(* N. ... *)` section into a named helper function (e.g., `schema_diff`, `align_rows`, `classify_rows`).

## WARNING: Float equality in `=` comparison

- **Line 648**: `try a = b with Invalid_argument _ -> false` uses OCaml structural equality (`=`) on floats, which is safe for NaN (returns false) but fragile for `-0.0` (`0.0 = -0.0` evaluates to `true`). For a diffing module this is unlikely to cause user-visible bugs, but it's inconsistent with the rest of the codebase that uses `Float.equal`.

  **Fix**: Use `Float.equal` explicitly for float comparisons, or constrain the catch-all to types where `=` is well-defined.

## INFO: List.hd guarded but still risky pattern

- **Line 792-794**: `List.hd missing_a` / `List.hd missing_b` — guarded by `if missing_a <> []` / `if missing_b <> []`, so safe in practice. But the pattern is fragile under refactoring (someone might remove the guard).

  **Fix**: Use `match missing_a with hd :: _ -> ... | [] -> ...` for compiler-enforced safety.

## INFO: Inconsistent error format in make_vdiff

- **Line 157-172**: `make_vdiff` returns `"detailed_diff"` and `"detailed_summary"` as duplicate keys with the same value (both set to `detailed_summary`). This is intentional per the VDiff envelope spec, but the duplication should be documented or deduplicated if the spec allows.

  **Fix**: Document why both keys carry the same value, or remove one if the downstream consumer is updated.

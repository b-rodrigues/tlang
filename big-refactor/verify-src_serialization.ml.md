# Verification: review-src_serialization.ml.md → src/serialization.ml

## File: src/serialization.ml
### Finding: invalid_arg raised for unsupported types in value_to_yojson (Original lines: 236-254, 294-295, 297-298)
**Actual line**: 236-254, 294-298
**Status**: CONFIRMED
**Evidence**: `value_to_yojson` returns `Yojson.Safe.t` (not a `result` type) but raises `invalid_arg` for VPipeline, VMetaPipeline, VLambda, VBuiltin, VFormula, VNDArray, VIntent, VNode, VExpr, VComputedNode, VFactor, VSerializer, VBuildLog, VPattern, VUnquote, VUnquoteSplice, VDynamicArg, VQuo, VEnv. The immediate caller `write_json` (line 472) catches this with `try/with exn -> Error (Printexc.to_string exn)`, so the API boundary is preserved. However, per AGENTS.md, functions should not raise raw OCaml exceptions on user-visible input paths.
**Verdict**: The review is correct that raising raw `Invalid_argument` violates the structured error convention. However, `value_to_yojson` is internal to this module (no `.mli` export confirmed by looking at callers — only `write_json` calls it within this file), so the blast radius is limited. Still worth fixing for consistency.
**Better fix**: Change return type to `(Yojson.Safe.t, string) result` and return `Error` instead of raising.

---

## File: src/serialization.ml
### Finding: invalid_arg in yojson_to_value and yojson_to_verror (Original lines: 425-426, 460-464)
**Actual line**: 425-426, 460-464
**Status**: CONFIRMED
**Evidence**: `yojson_to_value` raises at line 426 for unsupported Yojson constructors. `yojson_to_verror` raises at lines 460-464 for non-assoc input or missing "type" field. Callers `read_json` (line 479) and `read_verror_json` (line 487) wrap with `try/with`, so the API boundary is safe. But this still violates the "no raw exceptions" rule.
**Verdict**: Same situation as `value_to_yojson` — technically safe for current callers but violates project conventions.
**Better fix**: Return `Result` instead of raising.

---

## File: src/serialization.ml
### Finding: Marshal.from_* for deserialization (Original lines: 589, 599)
**Actual line**: 589 (`Marshal.from_bytes payload 0`), 599 (`Marshal.from_channel ic`)
**Status**: CONFIRMED
**Evidence**: OCaml's `Marshal` module can execute arbitrary code from crafted input. The code has a security notice at lines 524-527 stating that MD5 is not cryptographically secure and `.tobj` files should only be loaded from trusted sources. The digest check detects accidental corruption but not intentional tampering.
**Verdict**: The review correctly identifies the security concern. The code already documents the limitation. The finding is accurate.

---

## File: src/serialization.ml
### Finding: ensure_parent_dir uses recursion without depth limit (Original lines: 1-10)
**Actual line**: 1-10
**Status**: CONFIRMED (INFO)
**Evidence**: `ensure_parent_dir` recursively creates parent directories. With a deeply nested path (thousands of nonexistent directories), this could overflow the call stack. In practice, file paths exceeding a few dozen components are extremely rare.
**Verdict**: The review correctly identifies a theoretical risk. No practical fix needed for typical use cases.

---

## File: src/serialization.ml
### Finding: String.sub with validated indices (Original lines: 38, 44, 54, 98, 647-648, 653)
**Actual line**: Multiple
**Status**: CONFIRMED (INFO)
**Evidence**: All `String.sub` calls are properly guarded by length and prefix checks. No unsafe substring operations.
**Verdict**: Review correctly confirms these are safe. No changes needed.

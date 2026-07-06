# Review: src/serialization.ml

**Lines**: 606
**Severity summary**: 2 critical, 1 warning, 2 info

---

## CRITICAL: invalid_arg raised for unsupported types in value_to_yojson

- **Lines 236–254, 294–295, 297–298**: `invalid_arg "value_to_yojson: VPipeline is not supported for JSON serialization"` (and similar for `VMetaPipeline`, `VLambda`, `VBuiltin`, `VFormula`, `VNDArray`, `VIntent`, `VNode`, `VExpr`, `VComputedNode`, `VFactor`, `VSerializer`, `VBuildLog`, `VPattern`, `VUnquote`, `VUnquoteSplice`, `VDynamicArg`, `VQuo`, `VEnv`) — These raise OCaml `Invalid_argument` exceptions for types that cannot be serialized to JSON. While `write_json` catches these (line 472: `with exn -> Error (Printexc.to_string exn)`), any other caller of `value_to_yojson` that doesn't wrap in try/with will crash.

  **Fix**: Return a `(Yojson.Safe.t, string) result` from `value_to_yojson` instead of raising.

- **Lines 425–426, 460–464**: Same pattern for `yojson_to_value` and `yojson_to_verror` — `invalid_arg` raised on unexpected JSON structure.

  **Fix**: Return `Result` instead of raising.

## WARNING: Marshal.from_* for deserialization

- **Lines 589, 599**: `Marshal.from_bytes payload 0` and `Marshal.from_channel ic` are used to deserialize T values. OCaml's `Marshal` module has known security concerns (arbitrary code execution from untrusted input). The code has a comment noting this (lines 524–527), but the security posture is weak — only an MD5 digest check protects against tampering, which is explicitly noted as non-cryptographic.

  **Fix**: Consider adding a stronger integrity check or documenting that `.tobj` files must never be loaded from untrusted sources.

## INFO: ensure_parent_dir uses recursion without depth limit

- **Lines 1–10**: `ensure_parent_dir` recursively creates parent directories. If a very deep path is given (e.g., thousands of nested nonexistent directories), this could stack-overflow.

  **Fix**: Use an iterative approach or `Unix.mkdir` with `~p:true` (if available on the platform). Low risk in practice.

## INFO: String.sub with validated indices

- **Lines 38, 44, 54, 98, 647–648, 653**: All `String.sub` calls are properly guarded by length checks and prefix checks. No unvalidated substring operations.

  **Fix**: No action needed.

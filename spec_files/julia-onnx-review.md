# Review: Julia ONNX Support in T-Lang

## Conclusion

The current Julia ONNX story is **asymmetric**:

- **Loading / inference looks supported** through `ONNXRunTime.jl`.
- **Writing / export is not generally supported** for ordinary Julia ML model objects.

So the practical conclusion is: **the user's intuition is correct** — today, Julia support for `^onnx` is credible on the read side, but the write side is overstated.

## What T-Lang currently implements

The repository wires Julia ONNX support in several places:

- `src/serialization_registry.ml` registers both `jl_write_onnx` and `jl_read_onnx` for the `onnx` serializer.
- `src/pipeline/nix_emit_node.ml` injects:
  - `jl_read_onnx(path) = ORT.load_inference(path)`
  - `jl_write_onnx(model, path) = ONNX.write(path, model)`
- `src/pipeline/pipeline_dependency_requirements.ml` requires both `ONNXRunTime` and `ONNX` for Julia `^onnx`.

That means the pipeline emitter is prepared for both operations, but that does **not** by itself prove that Julia can export arbitrary trained models to ONNX.

## What is actually validated in-repo

Current tests only validate the plumbing, not end-to-end Julia ONNX export:

- `tests/test_serializers.ml` checks that the emitted Julia script contains `ORT.load_inference(path)` and `ONNX.write(path, model)`.
- `tests/package_manager/test_package_manager.ml` checks dependency analysis for Julia `^onnx`.

I did **not** find an end-to-end Julia test that:

1. trains or constructs a Julia model,
2. exports it with `serializer = ^onnx`,
3. reloads it successfully,
4. and verifies predictions.

So the repository currently proves **emission and dependency wiring**, not general Julia ONNX export correctness.

## Upstream Julia package reality

### `ONNXRunTime.jl`

`ONNXRunTime.jl` is clearly an inference/runtime package. Its documented high-level flow is:

```julia
import ONNXRunTime as ORT
model = ORT.load_inference(path)
model(inputs)
```

This aligns well with T-Lang's current `jl_read_onnx()` implementation.

### `ONNX.jl`

The main caveat is `ONNX.jl`.

Its current README states that it:

- supports saving and loading graphs as `Umlaut.Tape`,
- is still under reconstruction,
- and does **not** implement conversion to Flux.

That is much narrower than “export Julia models to ONNX”.

In other words, `ONNX.write(path, model)` may work for specific ONNX.jl graph objects, but it should **not** be treated as a general exporter for:

- `Flux.jl` models,
- `MLJ.jl` models,
- `DecisionTree.jl` models,
- `GLM.jl` models,
- or arbitrary Julia objects returned by a pipeline node.

## Practical interpretation for T-Lang

Today, Julia `^onnx` support should be described like this:

- **Supported:** consuming existing `.onnx` artifacts in Julia nodes via `ONNXRunTime.jl`.
- **Not yet generally supported:** exporting arbitrary Julia model objects to `.onnx`.
- **Possibly supported in narrow cases:** writing ONNX.jl-compatible graph objects, if a node explicitly constructs that representation first.

## Documentation mismatch found

There is an inconsistency in the repo:

- `docs/serializers.md`, `docs/api-reference.md`, and `summary.md` already describe Julia ONNX export as unsupported.
- `spec_files/finalizing-julia-support.md` still says ONNX read/write helpers are implemented and frames the remaining work mostly as hardening.
- `docs/changelog.md` currently says Julia has “Full support for ONNX model inference and export”, which appears too strong.

The conservative, evidence-based position is that **Julia ONNX read support exists, but Julia ONNX export should still be treated as experimental or unsupported** unless the supported Julia-side object type is made explicit and verified with end-to-end tests.

## Recommended next step

If T-Lang wants to claim Julia ONNX writing support, it should first define a narrow contract, for example:

- `jl_write_onnx()` only accepts a specific ONNX.jl graph type,
- or T documents a supported Julia model family plus the exact conversion path,
- and adds an end-to-end golden/integration test for that contract.

Until then, the safest product statement is:

> Julia can load and run ONNX artifacts, but general Julia-to-ONNX export is not yet a supported workflow.

## Phased plan to implement Julia ONNX writing

### Phase 1 — Narrow the contract

Start by making the supported write target explicit instead of claiming broad Julia model export.

- Define the first supported Julia-side input type for `jl_write_onnx()`.
- Prefer a **graph-level contract** first, such as ONNX.jl-compatible graph/tape objects, because that is closest to what upstream ONNX.jl documents today.
- Update the user-facing contract so unsupported Julia model families fail explicitly instead of appearing to be supported.

**Exit criteria:**

- `jl_write_onnx()` has a documented accepted input type.
- Unsupported Julia objects raise a clear runtime error.
- Docs stop implying generic Julia model export.

### Phase 2 — Harden the runtime helper

Once the contract is narrow, harden `jl_write_onnx()` around that contract.

- Add explicit type checks in the Julia helper before calling `ONNX.write(...)`.
- Improve the error message to say which Julia object types are accepted.
- Keep the current “no silent magic” rule: do not fall back to JLD2, JSON, or another format when ONNX export is requested.

**Exit criteria:**

- The write helper rejects unsupported objects deterministically.
- Failure messages tell the user how to make the object exportable.
- Dependency checks remain explicit for `ONNX` and any additional Julia packages required by the supported writer path.

### Phase 3 — Add one end-to-end supported export path

After the helper is hardened, add exactly one supported end-to-end export workflow.

- Pick one concrete Julia source model family or graph representation.
- Document the exact construction/conversion path inside a Julia node.
- Verify that the emitted `.onnx` artifact can be:
  1. written in a Julia node,
  2. read back by `jl_read_onnx()` or `t_read_onnx()`,
  3. and used for successful inference.

The safest initial target is likely an ONNX.jl-native graph representation, not `Flux.jl`, `MLJ.jl`, `GLM.jl`, or `DecisionTree.jl`.

**Exit criteria:**

- One Julia ONNX writer flow works end to end.
- A dedicated test proves write → read → predict.
- T-Lang documentation names that supported flow precisely.

### Phase 4 — Expand model-family coverage deliberately

Only after one narrow path works should T-Lang broaden support.

- Evaluate additional Julia model families one by one.
- For each family, define whether support is:
  - native via ONNX.jl,
  - supported through a conversion layer,
  - or explicitly unsupported.
- Avoid umbrella claims like “Julia ONNX export is supported” until the supported families are enumerated.

Candidate families to assess separately:

- `Flux.jl`
- `MLJ.jl`
- `GLM.jl`
- `DecisionTree.jl`

**Exit criteria:**

- Each claimed model family has a defined export contract.
- Each family has its own tests and documentation.
- Unsupported families still fail clearly.

### Phase 5 — Promote from experimental to supported

Only when multiple families are verified should the project upgrade the public claim.

- Update `docs/changelog.md`, `docs/serializers.md`, `docs/api-reference.md`, and `summary.md` together.
- Remove “experimental” wording only when coverage and tests justify it.
- Add CI coverage for Julia ONNX writing so regressions are caught automatically.

**Exit criteria:**

- Public docs are consistent.
- CI covers Julia ONNX write support.
- The supported Julia ONNX export surface is precise, tested, and reproducible.

## Evidence reviewed

### In-repo

- `src/serialization_registry.ml`
- `src/pipeline/nix_emit_node.ml`
- `src/pipeline/pipeline_dependency_requirements.ml`
- `tests/test_serializers.ml`
- `tests/package_manager/test_package_manager.ml`
- `docs/serializers.md`
- `docs/api-reference.md`
- `docs/changelog.md`
- `spec_files/finalizing-julia-support.md`

### Upstream package references

- `ONNXRunTime.jl` README: high-level API centered on `load_inference(...)`
- `ONNX.jl` README: “currently supports saving & loading graphs as a `Umlaut.Tape`” and “no conversion to Flux is implemented yet”
- Julia Discourse thread `Save Flux model to ONNX?`: discussion confirms the gap between graph-level support and general model export

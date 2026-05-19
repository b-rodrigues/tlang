# Specification: Finalizing Julia Support in T-Lang

This document outlines the remaining gaps and required implementations to bring Julia support to parity with R and Python runtimes in T-Lang.

## Current Status
- [x] Julia Companion Package (`tlang` helper) implemented with `read_node` and `pipeline_nodes`.
- [x] Basic Serializer Injections (CSV, JSON, Arrow) for Julia nodes.
- [x] Nix generator handles `JULIA_LOAD_PATH` and companion package provisioning.
- [x] Cross-language dependency wiring via `T_NODE_<name>` environment variables.

## Remaining Gaps (Revalidated)

### 1. Robust Native Serialization
**Status:** Implemented.

Julia runtime injection now includes a hardened `jl_serialize(obj, path)` implementation in `nix_emit_node.ml`.

- **Hardening:** Switched from `Serialization.serialize` to `JLD2.jldsave` as the default fallback for non-data types to ensure cross-process stability.
- **Safety:** Implemented explicit type guards to fail loudly when attempting to serialize fundamentally un-portable types (closures, tasks, IO streams).
- **Provisioning:** `JLD2` is now included in the default `juliaPkg` set and base `using` statements for all Julia nodes.

### 2. PMML & ONNX Export Support
**Status:** Mixed. PMML is implemented; Julia ONNX support is currently read-heavy and write support is not yet general.

- `t_pmml_jl_code` is implemented, including a GLM-focused PMML writer and a JPMML-backed reader.
- `t_onnx_jl_code` currently injects both `jl_read_onnx()` and `jl_write_onnx()`, but the write path calls `ONNX.write(path, model)` directly.
- `jl_read_onnx()` aligns with `ONNXRunTime.jl`'s documented inference workflow and is the strongest part of the integration.
- `jl_write_onnx()` should not be treated as a general Julia model exporter yet: upstream `ONNX.jl` documents graph-level save/load support, not broad automatic export for common Julia ML model families.
- **Next step:** implement Julia ONNX writing as a phased rollout, starting with a narrow, explicitly typed writer contract before any broader model-family claims.
- **See also:** `spec_files/julia-onnx-review.md`.

### 3. Runtime Diagnostics (`t doctor`)
**Status:** ~~Still a gap~~.

`t doctor` exists, but `package_doctor.ml` does not yet perform Julia-specific runtime diagnostics.
- **Goal**: Add checks to `package_doctor.ml` to verify:
    - `JULIA_LOAD_PATH` correctness.
    - Presence of mandatory packages (`JSON`, `DataFrames`, `CSV`, `Arrow`).
    - Basic Julia binary availability and version compatibility.

### 4. Visual Metadata Extraction
**Status:** Implemented for core Julia plot cases.

Metadata extraction and preview plumbing for Julia plot classes (including Makie-focused handling) exists in pipeline emission, and `show_plot` includes Julia rendering logic with explicit `CairoMakie` requirements for Makie.

- **Possible follow-up:** expand extraction coverage and metadata richness for additional plotting packages/types.

### 5. CI/CD Integration Testing
**Status:** Partially addressed through existing suite coverage.

There is already Julia-related coverage in the pipeline and CLI test suites (including Julia plot metadata/renderer behavior), but a dedicated `tests/julia/test_julia_integration.ml` target still does not exist.

- **Goal:** optionally add a dedicated Julia integration test file if clearer ownership/isolation is desired in CI.

## Updated Implementation Priority
~~1. **Diagnostics (`t doctor`)**: still missing Julia-specific checks and is the clearest operational gap.~~
2. **Serialization hardening**: `jl_serialize` exists but is still thin and should be made more robust/documented.
3. **Interoperability hardening for PMML/ONNX**: core helpers exist; prioritize broader model-family validation and tests.

## Details on serialization hardening

## Serialization Hardening for `jl_serialize` in T-Lang

The core risk named in the spec is real and well-known in Julia: `Serialization.serialize` is **process-local** by design. It serializes Julia's internal object graph, including compiled method references, module identity, and type cache state. When you deserialize in another process (or even the same process after recompilation), you can hit:

- **World-age violations** — a deserialized closure or method reference may point to a compiled specialization that no longer exists in the new process's world.
- **Method cache misses** — deserialized objects carrying type parameters may fail dispatch because the method table was rebuilt.
- **Module identity mismatches** — if the package versions differ even slightly between the serializing and deserializing process, type identity checks fail silently or loudly.

These are not edge cases for T-Lang: they're almost guaranteed to appear with any non-trivial fitted model (GLM, MLJ wrappers, Flux chains).

---

### Hardening strategy by object class

The right answer is a **tiered dispatch** inside `jl_serialize`, not a single universal fallback:

#### Tier 1 — Structured formats for known model families

For objects that have a well-defined external representation, skip `Serialization` entirely and use it:

| Model family | Recommended format |
|---|---|
| GLM.jl fitted models | PMML via your existing `t_pmml_jl_code` |
| Flux.jl chains | `Flux.state` → JLD2 (safe, version-stable) |
| MLJ models | MLJ's own `MLJ.save` / `MLJ.machine` serialization |
| DecisionTree.jl | JSON of tree structure or PMML if supported |
| Pure data (`DataFrame`, arrays) | Arrow (already wired) |

This means `jl_serialize` becomes a **dispatch table** keyed on type, not a passthrough.

#### Tier 2 — JLD2 as the general fallback

For objects not covered by Tier 1, `JLD2.jldsave` is significantly safer than `Serialization.serialize` across process boundaries because it:
- Serializes to HDF5-based format with type annotations
- Does not embed compiled method specializations
- Survives version bumps better (though not perfectly)

```julia
using JLD2

function jl_serialize(obj, path::String)
    if _is_glm_model(obj)
        _serialize_pmml(obj, path)          # your existing PMML path
    elseif _is_flux_model(obj)
        JLD2.jldsave(path * ".jld2"; model = Flux.state(obj))
    else
        JLD2.jldsave(path * ".jld2"; object = obj)
    end
end
```

#### Tier 3 — Explicit unsupported list with hard errors

For types that are fundamentally un-portable (closures capturing foreign state, anonymous types, task handles), fail **loudly at serialization time**, not at deserialization time in another node. This is critical for T-Lang's reproducibility contract — a silent corrupt artifact is far worse than a clear pipeline failure.

```julia
const UNSERIALIZABLE_TYPES = [Task, Channel, Base.IOStream]

function jl_serialize(obj, path::String)
    for T in UNSERIALIZABLE_TYPES
        obj isa T && error("T-Lang: $(typeof(obj)) is not cross-process serializable. \
                            Return a structured representation from this node instead.")
    end
    # ... dispatch to tier 1/2
end
```

---

### What to emit from `nix_emit_node.ml`

The OCaml side should probably track which serialization tier was used, so the downstream deserializer knows what to expect. You could encode this in the `T_NODE_<name>` environment variables or in a sidecar metadata file (`.tmeta`). Something like:

```
T_NODE_mymodel_FORMAT=jld2
T_NODE_mymodel_PATH=/path/to/mymodel.jld2
```

This avoids the deserializing node having to sniff the format, which is fragile.

---

### Implementation Summary: JLD2 Hardening (May 2026)

The serialization hardening strategy outlined above has been implemented in `src/pipeline/nix_emit_node.ml` and `src/pipeline/nix_emit_pipeline.ml`:

1.  **Mandatory Provisioning**: `JLD2` was added to the `julia_packages_injection` in `nix_emit_pipeline.ml`. This ensures the Nix sandbox always contains `JLD2` for any pipeline with Julia nodes.
2.  **Base Imports**: Every Julia node now includes `using JLD2` in its header, added via `runtime_base_packages` in `nix_emit_node.ml`.
3.  **Hardened `jl_serialize`**:
    - **Tiered Dispatch**: The implementation now prefers `JLD2.jldsave` for general objects.
    - **Validation**: Added checks for `Task`, `Channel`, `Base.IO`, and `Base.AbstractLock`, throwing a descriptive `T-Lang Julia serialization error` if encountered.
    - **Closure Protection**: Explicitly forbids serializing non-Type `Function` objects to prevent world-age and environment-capture crashes.
4.  **Verification**: Golden tests (including `julia_simple.t`) now successfully use this hardened path for cross-node data interchange within the Nix sandbox.

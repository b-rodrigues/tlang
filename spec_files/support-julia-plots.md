# Specification: Julia Plot Support for `make.jl`, `TidierPlots.jl`, `Plots.jl`, and `Makie.jl`

## Summary

T already gives R and Python plotting nodes a first-class experience:

- the node artifact is preserved
- a sibling `viz` JSON file is emitted with lightweight metadata
- `read_node()` returns metadata instead of the raw binary artifact
- `pretty_print` renders a specialized summary in the REPL
- `show_plot()` can materialize the plot into `_pipeline/` and open it

Julia nodes should follow the same contract.

The goal of this work is to make Julia plotting feel identical whether the user:

- writes inline Julia in `jl_node(command = <{ ... }>)`
- points at a script such as `jl_node(script = "make.jl")`
- returns a `TidierPlots.jl` ggplot-style object
- returns a `Plots.jl` plot object
- returns a `Makie.jl` figure-like object

This document describes the smallest coherent design to get there.

---

## Current State

Julia is already a first-class pipeline runtime, but plotting support is still R/Python-centric.

Today the relevant pieces already exist for R/Python:

1. `src/pipeline/nix_emit_node.ml`
   - detects supported plot objects
   - serializes the plot artifact
   - writes `viz` metadata JSON
   - writes the plot `class`
2. `src/packages/pipeline/read_node.ml` and `src/pipeline/builder_read_node.ml`
   - return `viz` metadata for recognized plot classes
3. `src/packages/core/pretty_print.ml`
   - renders a specialized tree view for recognized plot metadata classes
4. `src/packages/core/show_plot.ml`
   - knows which plot classes are supported
   - generates a runtime-specific render script
   - saves a PNG and opens it locally
5. `src/pipeline/pipeline_dependency_requirements.ml`
   - suggests plotting dependencies when R/Python plotting libraries are detected

Julia nodes already run through the same pipeline machinery, so `make.jl` does not need a separate execution model. The missing piece is plot-class detection, metadata extraction, and rendering support for Julia plotting objects.

---

## Scope

### In Scope

- Julia plots returned from inline `jl_node(...)` code
- Julia plots returned from `node(script = "make.jl", runtime = Julia, ...)` or `jl_node(script = "make.jl")`
- `TidierPlots.jl` plots
- `Plots.jl` plots
- `Makie.jl` plots
- REPL metadata display parity with current ggplot/Python support
- `show_plot()` support for built Julia plot nodes
- dependency discovery for the relevant Julia packages

### Out of Scope

- automatic support for every Julia visualization package
- new T syntax
- silent fallback from unsupported Julia plot objects to some other renderer

If a Julia object is not one of the explicitly supported classes, T should keep its current explicit behavior and surface a clear error.

---

## Target User Experience

### 1. `make.jl` works like `train.R` or `plot.py`

```t
p = pipeline {
  sales_plot = jl_node(script = "make.jl")
}

build_pipeline(p)
show_plot(read_node("sales_plot"))
```

If `make.jl` returns a supported Julia plot object, T should:

- preserve the Julia artifact
- emit `viz`
- let `read_node("sales_plot")` return metadata
- let `show_plot(read_node("sales_plot"))` render a PNG

### 2. `TidierPlots.jl` behaves like Julia's `ggplot2` analogue

For `TidierPlots.jl`, the metadata schema should mirror the existing `ggplot`/`plotnine` shape as closely as possible:

- `class`
- `backend`
- `title`
- `mapping`
- `labels`
- `layers`
- `_display_keys`

### 3. `Plots.jl` gets a simpler but still useful summary

For `Plots.jl`, the first iteration can be smaller:

- `class`
- `backend`
- `title`
- `labels`
- `layers`
- `_display_keys`

`mapping` is optional for `Plots.jl` and should only be added if it can be extracted without brittle introspection.

### 4. `Makie.jl` support should focus on figure-oriented inspection

For `Makie.jl`, the first iteration should target stable figure/container types rather than every interactive primitive.

Recommended metadata:

- `class`
- `backend`
- `title`
- `labels`
- `layers`
- `_display_keys`

`mapping` should remain optional for Makie because Makie is not grammar-of-graphics-first in the same way as `TidierPlots.jl`.

---

## Proposed Metadata Classes

Use stable lowercase class tags, consistent with the existing R/Python strings:

- `tidierplots`
- `plotsjl`
- `makie`

Do **not** use raw Julia type names as the public contract. Internal Julia types can change; the metadata class strings should remain stable.

Each metadata dict should also set:

- `backend = "Julia"`

This keeps `pretty_print`, `read_node()`, and downstream tooling uniform across runtimes.

---

## Artifact Contract

Julia plotting nodes should follow the same on-disk contract already used by R/Python plot nodes:

- `artifact` — serialized Julia plot object
- `class` — one-line file containing `tidierplots`, `plotsjl`, or `makie`
- `viz` — JSON metadata for inspection

This is important because the rest of the system already expects sibling files in that shape.

No special casing should be added for `make.jl` beyond the existing `script = "..."` execution path. If the script returns a supported plot object, the normal Julia plot machinery should handle it.

---

## Implementation Plan

### 1. Extend Julia plot detection in `src/pipeline/nix_emit_node.ml`

Add Julia equivalents of the current R/Python plot helpers:

- a Julia predicate that recognizes:
  - `TidierPlots.GGPlot`
  - `TidierPlots.GGPlotGrid` if grids are supported
  - `Plots.Plot`
  - `Makie.Figure`
  - `Makie.FigureAxisPlot` or equivalent figure-returning compound types if those are stable enough to support
- a Julia metadata extractor
- a Julia `save_viz_metadata` function
- Julia visual-class resolution that returns `tidierplots`, `plotsjl`, or `makie`

The extractor should be called in the same place where R/Python currently decide whether a node result is a plot and whether a `viz` file should be written.

### Metadata recommendations

#### `TidierPlots.jl`

Prefer extracting:

- title
- axis labels
- aesthetic mappings
- geom/layer names

Because `TidierPlots.jl` is explicitly ggplot-like, this is the closest Julia equivalent to the current R `ggplot` and Python `plotnine` handling.

#### `Plots.jl`

Start with:

- title
- axis labels
- series type names or subplot series names as `layers`

This should be intentionally conservative. The first version should prioritize stable extraction over deep introspection.

#### `Makie.jl`

Start with:

- figure title when one is present
- axis labels from the primary axis when they are easy to retrieve
- plot object or block type names as `layers`

Makie has a richer figure/layout model than `Plots.jl`, so the first version should extract only stable, figure-level metadata and avoid deep traversal of every scene graph detail.

---

### 2. Extend supported visual classes everywhere they are enumerated

Update all places that currently hard-code:

- `ggplot`
- `matplotlib`
- `plotnine`
- `seaborn`
- `plotly`
- `altair`

to also recognize:

- `tidierplots`
- `plotsjl`
- `makie`

The main files are:

- `src/packages/core/show_plot.ml`
- `src/packages/core/pretty_print.ml`
- `src/packages/pipeline/read_node.ml`
- `src/pipeline/builder_read_node.ml`

This keeps metadata reading and REPL display behavior consistent.

---

### 3. Add Julia rendering to `show_plot()`

`src/packages/core/show_plot.ml` needs a Julia renderer alongside the existing R/Python renderers.

### Runtime routing

- `tidierplots` -> Julia
- `plotsjl` -> Julia
- `makie` -> Julia

### Render strategy

Generate a `render_plot.jl` script in the sandbox and execute it with Julia.

Recommended first-pass behavior:

- for `Plots.jl` objects: `Plots.savefig(plot_obj, output_path)` or `savefig(plot_obj, output_path)`
- for `TidierPlots.jl` objects: `TidierPlots.ggsave(output_path, plot_obj)`
- for `Makie.jl` objects: activate a CPU-safe backend such as `CairoMakie` in the render script and call `save(output_path, figure_obj)`

This aligns with upstream package APIs:

- `Plots.jl` exposes `savefig`
- `TidierPlots.jl` exposes `ggsave`
- `Makie.jl` exposes `save`, and `CairoMakie` is the most appropriate first backend for reproducible headless rendering

The render script should preserve each library's native parameter order rather than wrapping them behind an invented helper, since the argument order is part of the upstream API contract.

The rendered output should remain a PNG written under `_pipeline/`, matching current `show_plot()` behavior.

---

### 4. Extend dependency discovery

`src/pipeline/pipeline_dependency_requirements.ml` should detect common Julia plotting imports:

- `using TidierPlots`
- `import TidierPlots`
- `using Plots`
- `import Plots`
- `using Makie`
- `import Makie`
- `using CairoMakie`
- `import CairoMakie`

and suggest the matching entries in `[julia-dependencies].packages`.

Minimum auto-detection:

- `TidierPlots`
- `Plots`
- `Makie`
- `CairoMakie`

#### Backend note for `Plots.jl`

`Plots.jl` relies on a plotting backend. T should not silently guess one.

So:

- detect `Plots`
- document that users must declare any backend package they rely on
- optionally add backend-specific detection later when the Julia source explicitly contains backend function calls
  - examples: `gr()`, `pythonplot()`, `plotlyjs()`
  - implement this as code-text detection of those call patterns, not import detection

This follows the codebase rule against silent magic.

#### Backend note for `Makie.jl`

Makie is backend-oriented, and the first supported rendering path should be explicit and headless.

So:

- detect `Makie`
- detect `CairoMakie` when users already declare it explicitly
- document that `show_plot()` support for Makie should standardize on `CairoMakie` for the first implementation
- do not silently switch between `GLMakie`, `WGLMakie`, and `CairoMakie`

This keeps rendering reproducible and avoids GPU/display assumptions inside the sandbox.

---

### 5. Tests

Add tests at the same layers currently used for R/Python plot support.

### Unit / pipeline tests

- Julia plot metadata extraction for a mocked `TidierPlots` node
- Julia plot metadata extraction for a mocked `Plots.jl` node
- Julia plot metadata extraction for a mocked `Makie.jl` node
- `read_node()` returning `viz` for recognized Julia plot classes
- `show_plot.render_script_for_class` accepting Julia classes

### CLI / pretty-print tests

- specialized pretty printing for `tidierplots`
- specialized pretty printing for `plotsjl`
- specialized pretty printing for `makie`

### Golden-style or integration tests

If the environment allows Julia plotting packages in CI:

- one end-to-end `jl_node(command = <{ ... }>)` example
- one `jl_node(script = "make.jl")` example

If CI cost is too high, a mocked artifact test like the existing plot metadata mock test is still valuable.

---

### 6. Documentation Updates

Once implemented, update:

- `docs/plotting.md`
- `docs/pipeline_tutorial.md`
- `README.md`
- `docs/changelog.md`

The docs should stop saying Julia plotting metadata is only "available" in a weak sense and instead describe the exact supported Julia plot classes.

---

## Suggested Delivery Order

1. Add metadata class names and `read_node` / `pretty_print` recognition
2. Add Julia metadata extraction in `nix_emit_node.ml`
3. Add Julia rendering in `show_plot.ml`
4. Add dependency discovery
5. Add tests
6. Update user-facing docs

This order keeps the implementation incremental while preserving a single final UX.

---

## Open Questions

These should be resolved during implementation, but they do not block the spec:

1. **Exact TidierPlots types**
   - confirm whether `GGPlot` and `GGPlotGrid` are the only user-facing plot return types to support initially
2. **Exact metadata accessors**
   - confirm which `TidierPlots.jl` fields are stable enough for title/mapping/layer extraction
   - confirm which `Plots.jl` attributes are stable enough for title/labels/layers extraction
   - confirm which `Makie.jl` figure/axis fields are stable enough for title/labels/layer extraction
3. **Makie return types**
   - decide whether the first version should support only `Figure` or also compound return values such as `FigureAxisPlot`
4. **Plots backend expectations**
   - decide whether the first version only documents explicit backend declaration or also auto-detects common backends

---

## Recommendation

Implement Julia plotting support by copying the existing R/Python plot contract, not by inventing a Julia-only path.

That means:

- same sibling artifact layout
- same `read_node()` behavior
- same REPL pretty-printing model
- same `show_plot()` workflow
- explicit dependency handling

`TidierPlots.jl` should be treated as the Julia analogue of `ggplot`/`plotnine`, `Plots.jl` should be treated as the Julia analogue of `matplotlib`, and `Makie.jl` should be treated as the figure-oriented Julia plotting system that gets explicit, headless rendering through `CairoMakie`: useful metadata, explicit rendering, and no hidden fallbacks.

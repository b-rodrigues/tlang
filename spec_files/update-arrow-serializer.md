# Update Arrow Serializer to Return Native Types (v0.54.2)

## Problem

Python's `^arrow` deserializer returns a `pandas.DataFrame` via `pyarrow.ipc.open_file(f).read_pandas()`. This forces every `pyn()` node that uses Polars to include `pl.from_pandas()` boilerplate — a silent round-trip through pandas that adds overhead and complexity.

Julia's `^arrow` deserializer converts `Arrow.Table` to a DataFrames.jl `DataFrame` eagerly, even when the consumer might want the lazy Arrow representation.

R's `^arrow` deserializer returns a tibble via `arrow::read_ipc_file(path)` — this is already the native R tabular type. No change needed.

## Current Behavior

| Runtime | Reader function | Returns | Writer |
|---|---|---|---|
| Python | `py_read_arrow` | `pandas.DataFrame` | Handles Polars (`.to_arrow()`) and pandas |
| R | `r_read_arrow` | tibble (native) | `as.data.frame()` coercion before write |
| Julia | `jl_read_arrow` | DataFrames.jl `DataFrame` | DataFrames.jl `DataFrame` |

Source: `src/pipeline/nix_emit_node.ml` lines 549-587.

## Proposed Changes

### Python (`nix_emit_node.ml:584-586`)

```python
# BEFORE
def py_read_arrow(path):
    with pa.OSFile(path, 'rb') as f:
        return ipc.open_file(f).read_pandas()

# AFTER
def py_read_arrow(path):
    with pa.OSFile(path, 'rb') as f:
        return ipc.open_file(f).read_all()
```

Returns `pyarrow.Table` instead of `pandas.DataFrame`. The IPC format on disk is unchanged — `pyarrow.Table` is the native Arrow in-memory type.

**Consumer patterns after change:**

```python
# Polars (zero-copy, no pandas)
df = pl.from_arrow(upstream_node)

# pandas (explicit conversion)
df = upstream_node.to_pandas()
```

### Julia (`nix_emit_node.ml:563-564`)

```julia
# BEFORE
function jl_read_arrow(path)
    Arrow.Table(path) |> DataFrame
end

# AFTER
function jl_read_arrow(path)
    Arrow.Table(path)
end
```

Returns lazy `Arrow.Table` instead of eagerly converting to DataFrames.jl `DataFrame`.

**Consumer patterns after change:**

```julia
# DataFrames.jl (explicit conversion)
df = DataFrame(upstream_node)

# Use directly (lazy Arrow access)
upstream_node  # Arrow.Table
```

### R — No change

`arrow::read_ipc_file(path)` returns a tibble, which is the native R tabular type. No round-trip through an intermediate format.

### Writer side — No change

- Python `py_write_arrow`: already handles Polars (via `.to_arrow()`), pandas, and raw Arrow Tables.
- Julia `jl_write_arrow`: `Arrow.write(path, df)` accepts DataFrames.jl directly.
- R `r_write_arrow`: `as.data.frame()` coercion is appropriate for R.

## Files to Modify

| File | Lines | Change |
|---|---|---|
| `src/pipeline/nix_emit_node.ml` | 584-586 | `read_pandas()` → `read_all()` |
| `src/pipeline/nix_emit_node.ml` | 563-564 | Remove `\|> DataFrame` |
| `spec_files/sandbox-interchange-protocol.md` | 1126 | Update doc: `.read_pandas()` → `.read_all()` |
| `agents/skill-t-project.md` | after line 28 | Add "Serialization & Language Boundaries" section |

## Skill File Addition

Add a new section `## Serialization & Language Boundaries` after "Choosing a node type" in `agents/skill-t-project.md`. Content:

### What each serializer returns in Python

| Serializer | Python receives | Convert to Polars |
|---|---|---|
| `^arrow` | `pyarrow.Table` | `pl.from_arrow(upstream_node)` |
| `^csv` | `pandas.DataFrame` | `pl.from_pandas(upstream_node)` |
| default (R `rn()`) | not directly usable | export via `^csv` or `^arrow` first |

### R → Python

Use `serializer = ^csv` on the R side:

```t
read_data = rn(
  command = <{ readxl::read_excel("data.xlsx") }>,
  serializer = ^csv
)

process = pyn(
  command = <{
import polars as pl
df = pl.from_pandas(read_data)
  }>,
  deserializer = ^csv,
  serializer = ^arrow
)
```

### Python → Python (Arrow, zero pandas)

Use `serializer = ^arrow` on both sides:

```t
clean = pyn(
  command = <{
import polars as pl
df = pl.from_arrow(raw)
  }>,
  deserializer = ^arrow,
  serializer = ^arrow
)
```

### Non-tabular outputs (plots, models)

ggplot objects, lm models, etc. cannot survive `^arrow` or `^csv` serialization.
Options:

1. **Default R serializer** — accessible via `read_node(p.node)` in post-build, but
   won't cross language boundaries.
2. **Save inside the node** — R/Python nodes can write files during the Nix build
   (e.g. `ggsave()`, `saveRDS()`). Use `pipeline_copy()` to extract them.
3. **Separate script** — export the data as CSV/Arrow, then generate plots in a
   standalone script outside the pipeline.

### Gotchas

- R's `^arrow` serializer calls `as.data.frame()` before writing. Non-data.frame R
  objects (ggplot, lm) will error.
- `t check --schema` does NOT validate serializer compatibility — only structure.
  A `^arrow` → `^csv` mismatch surfaces at runtime.
- The Python `^arrow` reader uses `pyarrow.ipc`, not Polars IPC. The on-disk format
  is identical, but the in-memory type is `pyarrow.Table`, not Polars DataFrame.

## Verification

1. `dune build` passes
2. `dune runtest` passes
3. Run a real T pipeline with Polars `pyn()` nodes — confirm `pl.from_arrow()` works end-to-end
4. Run a pipeline with Julia `jln()` nodes — confirm `DataFrame(upstream)` works
5. Run a pipeline with R `rn()` nodes — confirm no behavior change

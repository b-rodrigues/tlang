# Arrow in T

> Current user-facing guide to Arrow-backed DataFrames, Arrow IPC, and native-vs-fallback behavior

---

## Why Arrow matters in T

T uses Apache Arrow as the main storage and compute backend for DataFrames.

That gives the language a few important capabilities:

- columnar storage for DataFrames
- zero-copy numeric column views when native Arrow backing is active
- native compute kernels for operations such as filtering, sorting, arithmetic, comparisons, and grouped aggregation
- Arrow IPC read/write for file-based interchange
- Arrow-based interchange for multi-language pipeline nodes

The important practical detail is that T has a **dual-path** model:

- **Native Arrow path** when a DataFrame still has a live native Arrow handle
- **Pure OCaml fallback path** when a schema or operation cannot currently stay native

Both paths are supported. The difference is mostly about performance, memory layout, and interoperability.

---

## User stories

### 1. I want to work with a CSV in T and keep it fast

```t
df = read_csv("sales.csv")
explain(df).storage_backend
explain(df).native_path_active
```

Today, `read_csv()` returns an Arrow-backed DataFrame, but the public builtin currently parses CSV in OCaml first and then builds the Arrow-backed table. That means:

- you still get a DataFrame that can use the Arrow-native execution path,
- but the public CSV entry point is **not yet** the same thing as the lower-level native Arrow CSV reader in the backend.

If you need to know whether a later transformation stayed native, check `explain(df).storage_backend` and `explain(df).native_path_active`.

### 2. I want to save a DataFrame in Arrow format and load it back later

```t
df = read_csv("sales.csv")
t_write_arrow(df, "sales.arrow")

df2 = t_read_arrow("sales.arrow")
```

Use:

- `t_write_arrow(dataframe, path)` to write Arrow IPC data
- `t_read_arrow(path)` to read Arrow IPC data back into T

This is the most direct way to persist Arrow-backed tabular data without converting through CSV.

### 3. I want to pass DataFrames between T, R, and Python pipeline nodes

T pipelines can use Arrow as the serializer/deserializer boundary for DataFrames:

```t
train = read_csv("train.csv")

p = pipeline {
  prepare = train
  fit = node(
    command = <{
      fit_result <- prepare
    }>,
    runtime = R,
    serializer = "arrow",
    deserializer = "arrow"
  )
}
```

Arrow IPC is the supported DataFrame interchange story for pipeline nodes because it preserves columnar structure better than CSV and aligns with the native backend.

### 4. I want to know what stays native and what falls back

T aims to preserve native Arrow backing after supported operations, but not every schema can currently be rebuilt natively. The support matrix below shows the current state.

---

## Arrow I/O

### `t_read_arrow(path)`

Read an Arrow IPC file from disk and return a `DataFrame`.

```t
df = t_read_arrow("data.arrow")
```

### `t_write_arrow(dataframe, path)`

Write a `DataFrame` to an Arrow IPC file on disk.

```t
t_write_arrow(df, "snapshot.arrow")
```

### `read_csv(path, ...)` vs native Arrow CSV reading

There are currently two Arrow-related CSV stories in the repository:

1. **Public `read_csv()` builtin**
   - parses CSV in OCaml
   - performs type inference there
   - then constructs an Arrow-backed table

2. **Backend-native `Arrow_io.read_csv` path**
   - uses Arrow's native CSV reader
   - is currently used internally and in backend/performance testing
   - is **not yet** the public default CSV entry point

So users should think of `read_csv()` as **Arrow-backed output with an OCaml parsing front-end** for now.

---

## Support matrix

The table below summarizes the current user-visible state of Arrow support.

| Area | Current state |
|------|---------------|
| Primitive columns (`Int`, `Float`, `Bool`, `String`) | Fully supported on the native path |
| Filtering / sorting / projection | Native Arrow compute path available |
| Scalar arithmetic and comparisons | Native Arrow compute path available |
| Grouping and grouped aggregation | Native Arrow compute path available |
| Zero-copy numeric views | Supported for native numeric columns |
| Arrow IPC read/write | Supported via `t_read_arrow` / `t_write_arrow` |
| Pipeline DataFrame interchange | Supported via Arrow serializer/deserializer helpers |
| Dictionary / factor columns | Supported; native materialization exists |
| Date columns | Supported; native materialization exists |
| List / nested columns | Supported for the currently supported nested shapes; some cases still fall back |
| Datetime / timestamp columns | Partial support; parsing exists but native rebuild/materialization is still incomplete |
| Null-only columns | Fallback-only today |

### Rules of thumb

- If a table remains native-backed, `explain(df).native_path_active` returns `true`.
- Native backing is easiest to preserve for common primitive schemas.
- More complex structural transforms may rebuild successfully, but datetime and null-only columns are still important fallback cases.

---

## How to inspect the active backend

Use `explain()` when performance or interop matters:

```t
df = read_csv("example.csv")
explain(df).storage_backend
explain(df).native_path_active
```

Typical values:

- `"native_arrow"` when the DataFrame still has native Arrow backing
- `"pure_ocaml"` when the DataFrame has fallen back

---

## What is implemented today

At a high level, the current repository already includes:

- Arrow-backed DataFrame storage
- Arrow compute integration for common DataFrame operations
- Arrow IPC read/write builtins
- pipeline-level Arrow interchange
- dictionary/factor, list, and date support
- zero-copy numeric column access on native-backed tables

What is still incomplete is mostly about **surfacing and coverage**, not the existence of Arrow support itself:

- the public CSV path is not yet unified with the native Arrow CSV reader
- datetime/timestamp native rebuild is still incomplete
- null-only columns still fall back
- some historical planning documents still describe Arrow as earlier-stage than it is now

For deeper implementation status, see `arrow-current-status-next-steps.md`.

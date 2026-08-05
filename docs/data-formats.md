# Data I/O & Formats

T's data layer is built on [Apache Arrow](https://arrow.apache.org/): DataFrames
are backed by Arrow tables, and T provides fast native readers and writers for
the most common tabular formats. This guide explains how to load and save data,
which format to pick, and what to do when you need a format T does not read
natively.

---

## Choosing a Format

| Format | Functions | Best For | Notes |
|--------|-----------|----------|-------|
| **CSV** | `read_csv()` / `write_csv()` | Small-to-medium data, interchange with other tools | Human-readable; type inference; fast native path when using defaults |
| **Parquet** | `read_parquet()` / `write_parquet()` | Long-term storage, archival, large datasets, sharing with external analytics tools | Compressed, columnar, type-preserving; smaller on disk |
| **Arrow IPC** | `read_ipc()` / `write_ipc()` | Pipeline intermediates, cross-runtime exchange, fastest round trips | Zero-copy; no compression; also known as Feather v2 |
| **JSON** | `t_read_json()` / `t_write_json()` | Config, nested lists and dicts | See the [Serializers](serializers.md) guide for pipeline usage |

For a full decision walkthrough between Parquet and Arrow IPC, jump to
[Parquet vs Arrow IPC: How to Choose](#parquet-vs-arrow-ipc-how-to-choose).

All three tabular readers (`read_csv`, `read_parquet`, `read_ipc`) accept a
local path **or a URL**. For reproducible downloads inside pipelines, use
`fetchurl` with a pinned SHA-256 hash instead — see
[Downloading Data from URLs](#downloading-data-from-urls).

---

## Downloading Data from URLs

`read_csv`, `read_parquet`, and `read_ipc` all accept a URL in place of a
local path. How the download is handled depends on where you are running T.

### In the REPL or a script

The reader downloads the file to a temporary location, parses it, and removes
the temporary file. This is convenient for exploration, but the contents of a
URL can change between runs, so it is **not reproducible**.

```t
df = read_csv("https://example.com/data.csv")
```

If you want to keep a copy on disk, use `fetchurl`, which downloads immediately
via `curl`:

```t
fetchurl("https://example.com/data.csv", output = "data.csv")
```

### In a pipeline (reproducible downloads)

Pipeline builds run in the Nix sandbox, where downloads must be
content-addressed. Use `fetchurl` to create a node backed by Nix's
`builtins.fetchurl` with a pinned `sha256`, so every build fetches exactly the
same bytes:

```t
p = pipeline {
  raw = fetchurl("https://example.com/data.csv", sha256 = "sha256-abc123...")
  data = read_csv(raw) |> mutate($x > 0)
}
```

To obtain the hash for a URL, use `prefetch`. It runs `nix-prefetch-url`,
returns the SHA-256 hash, and seeds the file in the Nix store so the later
`fetchurl` build finds it cached and does not re-download:

```t
hash = prefetch("https://example.com/data.csv")
print(hash)  -- e.g. "sha256-abc123..."

p = pipeline {
  raw = fetchurl("https://example.com/data.csv", sha256 = hash)
  data = read_csv(raw) |> mutate($x > 0)
}

populate_pipeline(p, build = true)

-- The downloaded asset is available at p.raw.path after the build:
content = read_file(p.raw.path)
```

Notes on `fetchurl` nodes:

- `fetchurl` defaults to `serializer = ^bin`, so the node artifact is the raw
  downloaded bytes, ready for downstream T nodes to read.
- Pass `serializer = ^text` for plain-text assets (e.g. a JSON config file)
  that should be materialized as text.
- In pipeline mode, `sha256` is **required** — omitting it raises a `TypeError`.

See [Fetching Remote Assets](pipeline_tutorial.md#fetching-remote-assets) in the
Pipeline Tutorial and the [`fetchurl`](reference/fetchurl.md) /
[`prefetch`](reference/prefetch.md) reference pages for more details.

---

## CSV

`read_csv()` reads a CSV file into a DataFrame. For standard files it uses a
**native Arrow CSV reader** (`GArrowCSVReader`), which is significantly faster
and more memory-efficient than a pure OCaml parser for large datasets.

### When the Native Fast Path Is Used

The native Arrow reader is used automatically when you call `read_csv()` with
its default parameters:

- Comma separator (`,`)
- No skipping of the header or lines
- No automatic column name cleaning

If you pass any non-default option (`separator = ";"`, `skip_lines = 5`,
`clean_colnames = true`, …), T falls back to a pure OCaml CSV parser. This keeps
full compatibility with complex CSV layouts while providing maximum speed for
standard ones.

```t
df = read_csv("data.csv")                     -- native fast path
df = read_csv("data.csv", separator = ";")    -- OCaml parser
df = read_csv("https://example.com/data.csv") -- URL: see Downloading Data from URLs
```

### NA Handling

The native reader recognizes the following values as `NA`:

- `NA`
- `na`
- `N/A`
- Empty fields

This keeps the native reader consistent with the OCaml fallback parser.

### Fallback Behavior

If the native Arrow reader fails (e.g. malformed file or unsupported encoding),
T falls back automatically:

1. **Native attempt**: read with the Arrow CSV reader.
2. **Warning**: a warning is printed to stderr.
3. **OCaml fallback**: the file is re-read with the pure OCaml parser.

Note that the fallback is more memory-intensive and may hit `Out_of_memory`
errors for files larger than a few gigabytes on systems with limited RAM.

---

## Parquet

Parquet is the recommended format for large-scale data in T because it is:

- **Binary and columnar**, with built-in compression.
- **Type-preserving**, avoiding the overhead of type inference.
- **Fast to ingest**, using a native `parquet-glib` reader that is quicker than CSV reading.
- **Zero-copy loadable** into memory for large datasets.

```t
df = read_parquet("data.parquet")
write_parquet(df, "data.parquet")
```

---

## Arrow IPC (Feather v2)

Arrow IPC files (also known as Feather v2) give the fastest read/write round
trip and preserve the native Arrow storage model exactly. They are the ideal
choice for passing large DataFrames between runtimes.

```t
df = read_ipc("data.arrow")
write_ipc(df, "data.arrow")
```

Within a pipeline, DataFrames passed between T, R, Python, and Julia nodes use
Arrow IPC through the `^ipc` serializer — see the [Serializers](serializers.md)
guide and the [Pipeline Tutorial](pipeline_tutorial.md) for details.

---

## Parquet vs Arrow IPC: How to Choose

Parquet and Arrow IPC are both columnar, type-preserving, Arrow-native binary
formats. Every T runtime (T, R, Python, Julia) can read and write both, and
neither requires schema inference on load. The choice between them comes down
to **one question**: *is this data a live hand-off, or a durable artifact?*

- **Arrow IPC is the Arrow in-memory format flushed to disk.** Writing is
  effectively a memory dump, so it is the fastest format to write and read by
  a wide margin. In exchange, files are **uncompressed** by default and often
  several times larger than Parquet.
- **Parquet is a storage-optimized layout.** It applies block compression
  (snappy by default) and organizes data into row groups with column-level
  metadata, so files are smaller and readers can skip columns they do not need.
  Compression costs time at write time, but pays off at rest and for scans.

### Side-by-side comparison

| | Arrow IPC (`^ipc`) | Parquet (`^parquet`) |
|---|---|---|
| **File extension** | `.arrow` (also `.feather`) | `.parquet` |
| **Compression** | None by default | Snappy by default |
| **Relative file size** | Larger (uncompressed) | Typically 4–10× smaller for numeric data |
| **Write speed** | Fastest (memory dump) | Slower (compression + encoding) |
| **Read speed** | Fastest | Very fast; can skip whole columns |
| **Schema / type fidelity** | Exact | Exact |
| **Zero-copy / memory-map friendly** | Yes | No (must decode row groups) |
| **Cross-runtime support (T/R/Python/Julia)** | Symmetric | Symmetric |
| **Column pruning on read** | No | Yes (column metadata + row groups) |
| **External tool ecosystem** | Limited (Feather readers) | Broad (Spark, DuckDB, dask, pandas, Athena/BigQuery, …) |
| **Typical lifetime** | Minutes to hours | Days to years |

### Choose Arrow IPC when

- **The data is moving between nodes.** Within a pipeline, use `^ipc` to pass
  DataFrames between T, R, Python, and Julia nodes — it is T's default choice
  for exactly this reason.
- **You want the fastest possible round trip.** If a node reads, transforms,
  and writes data as an intermediate step, IPC avoids paying compression cost
  twice.
- **The artifact is short-lived or disposable** — a staging table, a scratch
  output, a cache.
- **You are memory-mapping large data** and want to avoid decoding overhead.

### Choose Parquet when

- **You are persisting a result.** Write final outputs, snapshots, and
  "published" datasets to Parquet so they stay small and readable for years.
- **Disk space or transfer cost matters.** Parquet's compression shrinks
  files dramatically, which also speeds up copying and uploads.
- **You are sharing data with the wider analytics ecosystem.** Spark, DuckDB,
  dask, pandas, BigQuery, and Athena all read Parquet natively; IPC is mostly
  confined to the Arrow ecosystem.
- **Downstream readers benefit from column pruning.** Analytics workloads
  that read a few columns from a wide table are much faster with Parquet.
- **You plan to append or scan subsets repeatedly.**

### Decision flow

```
Is the data only needed while the pipeline runs?
├─ Yes  → use ^ipc (fastest, no compression)
└─ No (you keep or share it) →
     Is it a durable artifact / shared with external tools?
     ├─ Yes → use ^parquet (compressed, columnar, interoperable)
     └─ No  → use ^ipc (speed) or ^parquet (smaller files) as you prefer
```

### Rule of thumb

Use **`^ipc`/`read_ipc`/`write_ipc` for anything that moves through a
pipeline**, and **`^parquet`/`read_parquet`/`write_parquet` for anything you
keep, ship, or store**. If you are unsure and the file is small, either works —
the formats are interchangeable at the API level (`read_parquet`/`write_parquet`
and `read_ipc`/`write_ipc` are drop-in replacements for each other).

> [!TIP]
> In a pipeline you can use both freely: pass data between nodes with `^ipc`
> for speed, and add a final node that materializes the result to Parquet with
> `write_parquet()` for storage. This gives you fast intermediates and small,
> shareable outputs.

---

## Formats T Does Not Read Natively

T does **not** ship parsers for proprietary office or statistical formats such
as Excel (`.xlsx`/`.xls`), SPSS (`.sav`), SAS, Stata (`.dta`), or similar. Do
not look for a `read_excel()` in T — it does not exist.

For these formats, use **R or Python** inside a pipeline node and let T
orchestrate the conversion:

1. **Declare the package** you need in `tproject.toml` — e.g. `readxl` or
   `openxlsx` (R), `pandas` or `polars` (Python) — under
   `[r-dependencies]` or `[py-dependencies]`, then run `t update`. See the
   [First Pipeline](first-pipeline.md) guide for declaring dependencies.
2. **Read the file in a node** and hand the result onward via a serializer:

```t
p = pipeline {
  raw = rn(
    command = <{
      library(readxl)
      read_excel("data.xlsx")
    }>,
    serializer = ^ipc
  )

  clean = node(
    command = raw |> filter($amount > 0),
    deserializer = ^ipc
  )
}
```

3. **Save from a node** the same way — write the file with the package of your
   choice inside an R or Python node, or convert with
   `write_csv()`/`write_parquet()` in T for downstream consumption.

This keeps T's standard library small and focused while giving you access to the
full ecosystem of R and Python readers, writers, and converters.

---

## Recommendations for Large Data

For datasets exceeding 2–3 GB:

1. **Prefer Parquet for storage**: convert CSVs to Parquet before reading them
   into T (e.g. with R's `arrow::write_parquet()` or Python's
   `pandas.DataFrame.to_parquet()`). See
   [Parquet vs Arrow IPC: How to Choose](#parquet-vs-arrow-ipc-how-to-choose)
   for when to reach for IPC instead.
2. **Use standard CSVs**: if you must use CSV, stick to the default comma
   separator and no leading comment lines to stay on the native fast path.
3. **Mind memory limits**: the pure OCaml fallback path is bounded by OCaml's
   heap and string-size limits — still large on 64-bit systems, but less
   efficient than Arrow's memory mapping.

---

## Related Guides

- [Performance](performance.md) — how the Arrow backend works, vectorization, and the native vs. fallback paths
- [Serializers in T](serializers.md) — `^ipc`, `^csv`, `^json`, and custom serializers for pipelines
- [Pipeline Materialization](pipeline-materialization.md) — how node artifacts are stored and read back
- [Function Reference](reference/index.html) — `read_csv`, `write_csv`, `read_parquet`, `write_parquet`, `read_ipc`, `write_ipc`

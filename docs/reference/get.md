# get

Unified retrieval for variables, collection elements, pipeline nodes, or lens focuses.

## Modes

### 1. Variable Lookup
With a single string or symbol argument, `get()` performs an R-style variable lookup.

```t
x = 42
get("x")             -- 42
get(to_symbol("x"))  -- 42
```

### 2. Data-Mask Aware Lookup (inside NSE verbs)
When called inside an NSE data verb (`mutate`, `filter`, `summarize`, …), `get()` checks the **data mask** (`row` binding) before the global environment. If the name matches a column in the current row or DataFrame, the column value is returned; otherwise it falls back to the global environment.

```t
df = dataframe(a = [1, 2, 3])
x = 42
df |> mutate(b = \(row) get("a"))  -- column from data mask
df |> mutate(c = \(row) get("x"))  -- not a column, falls back to global
```

### 3. Collection Indexing
With a collection and an integer index, `get()` retrieves the element at that 0-based position.

```t
get([10, 20, 30], 1)   -- 20
get(Vector[10, 20], 0) -- 10
```

### 4. Pipeline Node Access
With a pipeline and a string, `get()` retrieves the named node.

```t
p = pipeline { a = 1 }
get(p, "a")            -- 1
```

### 5. Lens Focus
With a data structure and a Lens, `get()` retrieves the focused value.

```t
get(df, col_lens("mpg"))
get(df, row_lens(0))
```

## Parameters

- **target** (`Any`): The data structure to retrieve from — a string/symbol name, a collection, a pipeline, or a lens-targetable structure.
- **selector** (`Any`, *optional*, default `NA`): An index, lens, or node name.
- **default** (`Any`, *optional*, default `NA`): A fallback value returned when `target` is `NA` or an `Error`.

## Returns

The retrieved value, or the `default` if `target` is `NA`/`Error`.


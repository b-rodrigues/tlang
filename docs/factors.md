# Factors and `fct_*` Helpers in T

This guide explains how factors work in T, when to use `factor()` versus `fct()`, and how the `fct_*` family helps you reorder, relabel, and combine categorical data.

---

## The Basic Idea

A factor is categorical data with an explicit list of levels.

That level list matters because operations such as `arrange()` use the level order instead of alphabetical order.

```t
sizes = factor(["medium", "small", "large"], levels = ["small", "medium", "large"])
levels(sizes)
-- ["small", "medium", "large"]
```

This makes factors useful for ordered categories such as:

- shirt sizes,
- survey responses,
- month names,
- reporting buckets.

---

## Creating Factors

### `factor()` — explicit categorical levels

Use `factor()` when you want to control the level order yourself.

```t
priority = factor(
  ["medium", "low", "high", "medium"],
  levels = ["low", "medium", "high"]
)
```

If you do not provide `levels`, `factor()` derives them from the data.

### `fct()` — levels follow first appearance

Use `fct()` when you want levels to keep the order in which values first appear.

```t
status = fct(["new", "in_progress", "done", "new"])
levels(status)
-- ["new", "in_progress", "done"]
```

### `as_factor()` — coerce existing values

`as_factor()` is the convenient coercion form for turning an existing vector or column into factor data.

```t
df |> mutate($segment = as_factor($segment))
```

### `ordered()` — ordered factors

Use `ordered()` when the order is meaningful and should be preserved as an ordered factor.

```t
ratings = ordered(
  ["bad", "ok", "great"],
  levels = ["bad", "ok", "great"]
)
```

---

## Why the `fct_*` Prefix Exists

The `fct_*` prefix is used for helpers that manipulate factor levels after creation.

These helpers are analogous to the factor tools popularized by `forcats` in R:

- they keep the input as factor data,
- they operate on levels or factor ordering,
- and they make factor-specific intent obvious in a pipeline.

Examples:

```t
fct_infreq(x)
fct_rev(x)
fct_recode(x, LARGE = "large")
fct_reorder(x, scores)
fct_lump_n(x, n = 3)
```

---

## Core Factor Workflow

### Inspect levels

```t
levels(priority)
```

### Reorder levels by frequency

```t
df |> mutate($segment = fct_infreq($segment))
```

### Reverse the current order

```t
df |> mutate($segment = fct_rev($segment))
```

### Recode level names

```t
df |> mutate($segment = fct_recode($segment, ENTERPRISE = "enterprise", SMB = "small_business"))
```

### Reorder levels using another variable

```t
df |> mutate($segment = fct_reorder($segment, $revenue))
```

### Move selected levels to the front or after a position

```t
df |> mutate($segment = fct_relevel($segment, "enterprise", "midmarket"))
```

### Collapse several levels into broader groups

```t
df |> mutate($segment = fct_collapse($segment, commercial = ["enterprise", "midmarket"], self_serve = "small_business"))
```

---

## Lumping and "Other"

The `fct_lump_*` helpers keep the most important levels and group the rest into an `Other` bucket by default.

### Keep the top `n` levels

```t
fct_lump_n($species, n = 2)
```

### Keep levels with at least a minimum count

```t
fct_lump_min(fct(["a", "a", "b", "c"]), 2)
levels(fct_lump_min(fct(["a", "a", "b", "c"]), 2))
-- ["a", "Other"]
```

### Keep levels above a minimum proportion

```t
fct_lump_prop($segment, 0.10)
```

You can also set a custom replacement label with `other_level = "Misc"`.

---

## Other Useful Helpers

### Keep or drop selected levels with `fct_other()`

```t
levels(fct_other(fct(["a", "b", "c"]), keep = ["a"]))
-- ["a", "Other"]
```

### Remove unused levels with `fct_drop()`

```t
levels(fct_drop(factor(["a", "b"], levels = ["a", "b", "c"])))
-- ["a", "b"]
```

### Add levels without changing existing values with `fct_expand()`

```t
levels(fct_expand(fct(["a"]), "b", "c"))
-- ["a", "b", "c"]
```

### Combine factors with unified levels using `fct_c()`

```t
levels(fct_c(fct(["a"], levels = ["a", "b"]), fct(["c"])))
-- ["a", "b", "c"]
```

---

## Sorting with Factors

A factor keeps its declared level order during sorting.

```t
df = crossing(size = ["medium", "small", "large"], id = [1, 2])

df
  |> mutate($size_fct = factor($size, levels = ["small", "medium", "large"]))
  |> arrange($size_fct)
```

This sorts rows by `small`, then `medium`, then `large`, even though alphabetical order would be different.

---

## Choosing the Right Helper

Use:

- `factor()` when you want explicit levels,
- `fct()` when you want first-appearance order,
- `as_factor()` when coercing an existing column,
- `ordered()` when the factor should be marked as ordered,
- `fct_*` helpers when changing levels after creation,
- `levels()` when you need to inspect the current level set.

---

These factor helpers are currently implemented alongside the data-manipulation verbs in T's `colcraft` package, but the naming convention is the same idea you would expect from a dedicated factor-toolkit family: factor creation helpers plus `fct_*` level-manipulation helpers.

---

## Next Steps

Now that you can handle categorical data, explore vector operations and statistical modeling in T:

1. **[Arrays and Matrices](arrays.md)** — Vector and matrix operations.
2. **[Formulas and Models](formulas.md)** — Statistical modeling in T.
3. **[Pipeline Tutorial](pipeline_tutorial.md)** — Build reproducible data pipelines.
4. **[API Reference](api-reference.md)** — Complete function reference by package.

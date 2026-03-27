# Composable Lenses: Reaching the Unreachable

> How to navigate and transform nested data structures that were previously painful or impossible to reach.

Traditional data manipulation verbs like `mutate()`, `filter()`, and `arrange()` are designed for flat DataFrames. Once your data becomes multi-dimensional—whether through nesting DataFrames (`nest()`) or building complex Pipelines—standard verbs often lead to a "pyramid of doom."

Lenses solve this by providing a first-class, composable way to "zoom in" on nested values and transform them surgically.

---

## Part I: Why Lenses

### 1. The Core Problem: Deeply Nested Structures

Consider a dataset that is genuinely hierarchical: a `clients` DataFrame where each row's `projects` column holds another DataFrame of that client's projects, and each project's `milestones` column holds a further DataFrame of milestones. Each client has a different number of projects; each project has a different number of milestones. This kind of structure arises naturally after a `nest()` call, or when loading hierarchical data from a JSON API.

```t
-- clients: DataFrame
--   $name     : String
--   $projects : DataFrame (nested)
--       $title      : String
--       $milestones : DataFrame (nested)
--           $label   : String
--           $pct_int : Int    -- completion percentage, 0–100
```

A business requirement: **apply a 10-point uplift to every milestone's `$pct_int` value** (an end-of-quarter adjustment). Because the number of milestones varies per project and per client, you cannot simply `mutate($pct_int = $pct_int + 10)` on the top-level DataFrame—`$pct_int` lives three levels down.

#### The Nested Mutate Approach (The "Pyramid of Doom")

With standard verbs you have to peel back every layer manually, inventing a new lambda variable at each level:

```t
updated_clients = clients |> mutate(
  $projects = map($projects, \(proj)
    proj |> mutate(
      $milestones = map($milestones, \(ms)
        ms |> mutate($pct_int = min($pct_int + 10, 100))
      )
    )
  )
)
```

This is fragile: rename a column or add another level of nesting and you rewrite the entire block. The deeper the hierarchy, the worse it gets.

#### The Lens Approach (Declarative Pathing)

Lenses let you declare the **path** to the target once, then apply it in a single operation. T handles traversal and immutable reconstruction automatically.

```t
-- Define the path once; compose() is variadic
pct_l = compose(col_lens("projects"), col_lens("milestones"), col_lens("pct_int"))

-- Apply the transformation everywhere in one line
updated_clients = clients |> over(pct_l, \(x) min(x .+ 10, 100))
```

**Why lenses win:**

1. **Readability**: The path is declared once; the operation is a single flat expression.
2. **Vectorization**: `over()` distributes your function across all matching values at every level automatically. When the focused value is a Vector (as it is here), broadcasting operators like `.+` and `.*` are required for element-wise operations; scalar operators will not work as intended.
3. **Reuse**: Name a lens once and use it with `get()`, `set()`, or `over()` anywhere in the codebase.

---

### 2. The Problem: Surgical Edits to Pipelines

Pipelines in T are often treated as immutable specifications. If you needed to change an environment variable for a deep node or update a cached result before building, you previously had to reconstruct the pipeline or use internal hacks.

#### The Solution: Orchestration Lenses

Specialized lenses allow you to treat a Pipeline as a queryable data structure.

- **`node_lens(node_name)`**: Targets the cached result value of a specific node.
- **`env_var_lens(node_name, var_name)`**: Targets a specific environment variable for a given node.

```t
p = build_pipeline("complex_analysis.t")

-- Inject a debug flag into a specific node's environment
debug_l = env_var_lens("compute_stats", "DEBUG")
p_debug = p |> set(debug_l, "true")

-- Re-run with the updated environment
build_pipeline(p_debug)
```

---

## Part II: Lens API

### 3. Core Operations

| Function | Signature | Description |
| :--- | :--- | :--- |
| **`set(data, lens, value)`** | `(A, Lens, B) -> A` | Replaces the focused value. |
| **`over(data, lens, f)`** | `(A, Lens, B -> B) -> A` | Applies a function to the focused value. |
| **`modify(data, lens1, f1, ...)`** | `(A, Lens, B -> B, ...) -> A` | Applies multiple lens+function pairs in sequence. |
| **`compose(...)`** | `(...Lens) -> Lens` | Chains lenses into a single path (left-to-right). |

> **Broadcasting**: When `over()` focuses on a column, the function receives a **Vector**. Use broadcasting operators (`.+`, `.*`, etc.) for element-wise math, not scalar operators. This applies at every level of a nested traversal.

#### `modify()`: Multiple transformations in one call

When you need to transform several paths in one operation, `modify()` keeps the update list flat and readable instead of chaining multiple `over()` calls.

```t
-- Two distinct paths through the same nested structure
pct_l   = compose(col_lens("projects"), col_lens("milestones"), col_lens("pct_int"))
label_l = compose(col_lens("projects"), col_lens("milestones"), col_lens("label"))

updated_clients = clients |> modify(
    pct_l,   \(x) min(x .+ 10, 100),
    label_l, \(s) s + " ✓"
)
```

---

### 4. Primitive Lenses

#### `col_lens(name)`

Targets a column in a DataFrame, a key in a Dictionary, or a named field in a nested record. This is the primary building block for navigating hierarchical structures.

```t
employees = dataframe([[name: "Alice", salary: 50000],
                       [name: "Bob",   salary: 48000]])

salary_l = col_lens("salary")

-- Replace values
raised   = employees |> set(salary_l, [60000, 58000])

-- Transform values
after_tax = raised |> over(salary_l, \(x) x .* 0.75)
```

#### `idx_lens(index)`

Focuses on a single 0-based index in a **List** or **Vector**.

```t
scores = [10, 20, 30]

-- Correct the second score
scores2 = scores |> set(idx_lens(1), 99)  -- [10, 99, 30]
```

#### `row_lens(index)`

Focuses on a specific row in a **DataFrame**. Compose with `col_lens` for cell-level access.

```t
df  = dataframe([[x: 1, y: 10], [x: 2, y: 20]])

-- Update a single cell (row 0, column "y")
df2 = df |> set(compose(row_lens(0), col_lens("y")), 99)
```

---

### 5. Traversals: `filter_lens`

> **Note:** `filter_lens` is a **traversal**, not a lens—it focuses on *multiple* elements simultaneously rather than a single one. Unlike a lens, which always focuses on exactly one location, a traversal may focus on zero, one, or many locations. Composition with other lenses works via the same `compose()` function, but the update function is applied independently to each matched element, and the results are written back into their original positions.

`filter_lens(predicate)` focuses on every element or row satisfying a condition. It works on **Lists**, **Vectors**, and **DataFrames**.

```t
scores = [1, 2, 3, 4, 5]

-- Add 10 to every even number
scores2 = scores |> over(filter_lens(\(x) x % 2 == 0), \(x) x + 10)
-- [1, 12, 3, 14, 5]
```

When composing a traversal with another lens, pass both to `compose()`. Do **not** use `|>` inside an argument position—the operator precedence will cause the expression to parse incorrectly:

```t
-- Correct: both arguments to compose()
df |> set(compose(filter_lens(\(r) r.status == "expired"), col_lens("val")), 0)

-- Wrong: |> inside an argument position parses incorrectly
-- df |> set(filter_lens(\(r) r.status == "expired") |> compose(col_lens("val")), 0)
```

For flat-DataFrame conditional updates, `mutate()` with `if_else()` is often simpler and more familiar:

```t
-- Equivalent, and clearer for the flat case
df |> mutate($val = if_else($status == "expired", 0, $val))
```

The traversal form pays off when the condition and transformation live inside a *nested* structure—for example, when `df` is itself a column inside a larger DataFrame and a top-level `mutate` cannot reach the target field.

---

### 6. API Quick Reference

| Function | Signature | Use Case |
| :--- | :--- | :--- |
| **`set(data, lens, value)`** | `(A, Lens, B) -> A` | Replaces the focused value. |
| **`over(data, lens, f)`** | `(A, Lens, B -> B) -> A` | Transforms the focused value. |
| **`modify(data, lens1, f1, ...)`** | `(A, Lens, B -> B, ...) -> A` | Multiple lens+function pairs in one call. |
| **`compose(...)`** | `(...Lens) -> Lens` | Chains any number of lenses into one path. |
| **`col_lens(name)`** | `String -> Lens` | Column/key/field focus. |
| **`node_lens(name)`** | `String -> Lens` | Pipeline node focus. |
| **`env_var_lens(n, v)`** | `(String, String) -> Lens` | Pipeline env var focus. |
| **`idx_lens(i)`** | `Int -> Lens` | List/Vector index focus. |
| **`row_lens(i)`** | `Int -> Lens` | DataFrame row focus. |
| **`filter_lens(p)`** | `Function -> Traversal` | Condition-based multi-focus. |

---

### Best Practices

1. **Name your paths**: Store commonly used lenses as named variables (`pct_l`, `salary_l`) and reuse them across `get`, `set`, and `over` calls.
2. **Encapsulation**: When building packages, export lenses for your internal data structures so users can extend your logic without knowing column names.
3. **Prefer standard verbs for flat DataFrames**: Lenses shine in nested or polymorphic contexts. For straightforward flat-DataFrame operations, `mutate()` and `filter()` are simpler and more idiomatic.

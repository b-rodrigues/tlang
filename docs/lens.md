# Composable Lenses: Reaching the Unreachable

> How to navigate and transform nested data structures that were previously painful or impossible to reach.

Traditional data manipulation verbs like `mutate()`, `filter()`, and `arrange()` are designed for flat DataFrames. Once your data becomes multi-dimensional—whether through nesting DataFrames (`nest()`) or building complex Pipelines—standard verbs often lead to a "pyramid of doom."

Lenses solve this by providing a first-class, composable way to "zoom in" on nested values and transform them surgically.

---

## 1. The Core Transformation: Lenses vs. Nested Mutates

When your data is flat, `mutate()` is perfect. But as soon as you have **nested DataFrames** (e.g., a "World" table containing "Countries", which contain "Cities", which contain "Neighborhoods"), standard verbs force you into a **Pyramid of Doom**.

### The Nested Mutate approach (The "Pyramid of Doom")
To update a value three levels deep, you have to manually traverse every layer using `map()` and `mutate()`. Notice how you must invent new lambda variables (`c`, `nb`) for every level:

```t
-- Increasing population by 5% three levels deep
updated_world = world |> mutate(
  $countries = map($countries, \(c) 
    c |> mutate(
      $cities = map($cities, \(nb) 
        nb |> mutate($population = $population * 1.05)
      )
    )
  )
)
```
This is fragile: if the schema changes, you have to rewrite the entire block. It's also hard to read and easy to make a mistake in the nesting.

### The Lens Approach (Declarative Pathing)
Lenses allow you to define the **path** to the data once, and then apply it in a single operation. T handles the deep traversal and reconstruction of the immutable structure automatically.

```t
-- Define the path once
-- compose() is variadic and accepts any number of lenses
pop_l = compose(col_lens("countries"), col_lens("cities"), col_lens("population"))

-- Perform the surgical update
updated_world = world |> over(pop_l, \(x) x .* 1.05)
```

#### Why Lenses Win:
1.  **Readability**: The operation is a single flat line, not a 7-level nested block.
2.  **Vectorization**: Lenses in T are **fully vectorized**. The `over` function automatically distributes your transformation across all rows at every level of the hierarchy.
3.  **Reuse**: You can define `pop_l` as a variable and use it for `get()`, `set()`, or `over()` across your entire project.

---

## 2. The Problem: Surgical Edits to Pipelines

Pipelines in T are often treated as immutable specifications. If you needed to change an environment variable for a deep node or update a cached result before building, you previously had to reconstruct the pipeline or use internal hacks.

### The Solution: Orchestration Lenses
Specialized lenses allow you to treat a Pipeline as a queryable data structure.

*   **`node_lens(node_name)`**: Targets the cached result value of a specific node.
*   **`env_var_lens(node_name, var_name)`**: Targets a specific environment variable for a given node.

```t
p = build_pipeline("complex_analysis.t")

-- Injection of a debug flag into a specific node's environment
debug_l = env_var_lens("compute_stats", "DEBUG")
p_debug = p |> set(debug_l, "true")

-- Re-running with the new environment
build_pipeline(p_debug)
```

---

## 3. Beyond the Impossible: Standard DataFrames

While lenses excel at solving nesting problems, they also provide a unified interface for standard DataFrames. If you are writing a generic function that should work across different schemas, lenses are your best friend.

### `col_lens(name)`
Targets a column in a DataFrame or a key in a Dictionary.

```t
employees = dataframe([[name: "Alice", salary: 50000]])

salary_l = col_lens("salary")

-- Update a single field
updated = employees |> set(salary_l, [60000])

-- Transform a field
final = updated |> over(salary_l, \(x) x .* 0.9)
```

---

## 4. API Reference Summary

| Function | Signature | Use Case |
| :--- | :--- | :--- |
| **`set(data, lens, value)`** | `(A, Lens, B) -> A` | Replaces the focused value. |
| **`over(data, lens, f)`** | `(A, Lens, B -> B) -> A` | Transforms the focused value. |
| **`modify(data, lens1, f1, ...)`** | `(A, Lens, B -> B, ...) -> A` | Applies multiple lens transformations in sequence. |
| **`compose(...)`** | `(...Lens) -> Lens` | Chains any number of lenses into one path. |
| **`col_lens(name)`** | `String -> Lens` | Generic column/key focus. |
| **`node_lens(name)`** | `String -> Lens` | Pipeline node focus. |
| **`env_var_lens(n, v)`** | `(Str, Str) -> Lens` | Pipeline env var focus. |

---

### 5. Multi-transformation with `modify()`

When you need to perform multiple distinct transformations on a complex structure, `modify()` is significantly more powerful and readable than chaining multiple `over()` calls. It handles the intermediate states and passes the result through each transformation sequentially.

**Scenario: Updating a nation's name AND its cities' populations in one operation.**

```t
-- Defining the two distinct paths
capital_l = compose(col_lens("countries"), col_lens("capital"))
pop_l     = compose(col_lens("countries"), col_lens("cities"), col_lens("population"))

-- Apply heterogeneous transformations in a single pass
-- This avoids multiple traversals of the 'world' structure.
updated_world = world |> modify(
    capital_l, \(c) c + " (Verified)",
    pop_l,     \(p) p .* 1.05
)
```

To achieve this with standard verbs, you would need to nest your `mutate` logic inside another `mutate` logic, and then rebuild the entire tree—a process that quickly becomes unmanageable as the number of paths grows. `modify()` keeps the update list flat and declarative.

---

### Best Practices

1.  **Broadcasting**: When using `over()` on a column lens, the function receives a **Vector**. Use broadcasting operators like `.*` for element-wise math.
2.  **Naming**: Store your common paths as named lenses: `sales_data_l = compose(col_lens("results"), col_lens("sales"))`.
3.  **Encapsulation**: When building packages, export lenses for your internal data structures so users can extend your logic without knowing your column names.

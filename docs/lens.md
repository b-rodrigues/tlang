# Composable Lenses: Reaching the Unreachable

> How to navigate and transform nested data structures that were previously painful or impossible to reach.

Traditional data manipulation verbs like `mutate()`, `filter()`, and `arrange()` are designed for flat DataFrames. Once your data becomes multi-dimensional—whether through nesting DataFrames (`nest()`) or building complex Pipelines—standard verbs often lead to a "pyramid of doom."

Lenses solve this by providing a first-class, composable way to "zoom in" on nested values and transform them surgically.

---

## 1. The Problem: Nested DataFrame "Pyramid of Doom"

Suppose you have a DataFrame where each row contains another DataFrame (a nested list-column). Your goal is to increase the `salary` field inside those sub-tables by 10%.

### The Old Way (Painful)
Before lenses, you had to nest your logic using `mutate` combined with `map`:

```t
-- This is verbose and error-prone as nesting depth increases
nested_updated = nested |> mutate(
  $data = map($data, \(inner_df) {
    inner_df |> mutate($salary = $salary * 1.1)
  })
)
```

### The Lens Way (Elegant)
With lenses, you define a **composition** that reaches exactly where you want to go. T understands the vectorization automatically.

```t
-- Target 'salary' INSIDE 'data'
nested_salary_l = compose(col_lens("data"), col_lens("salary"))

-- One clean operation
nested_updated = nested |> over(nested_salary_l, \(x) x .* 1.1)
```

The `over()` function takes the complex structure, the lens, and a transformation function. It drills down, applies the function, and builds the updated structure back up on its way out.

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
| **`compose(L1, L2)`** | `(Lens, Lens) -> Lens` | Chains focus from L1 into L2. |
| **`col_lens(name)`** | `String -> Lens` | Generic column/key focus. |
| **`node_lens(name)`** | `String -> Lens` | Pipeline node focus. |
| **`env_var_lens(n, v)`** | `(Str, Str) -> Lens` | Pipeline env var focus. |

---

### Best Practices

1.  **Broadcasting**: When using `over()` on a column lens, the function receives a **Vector**. Use broadcasting operators like `.*` for element-wise math.
2.  **Naming**: Store your common paths as named lenses: `sales_data_l = compose(col_lens("results"), col_lens("sales"))`.
3.  **Encapsulation**: When building packages, export lenses for your internal data structures so users can extend your logic without knowing your column names.

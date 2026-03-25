# Composable Functional Lenses

> A modern tutorial on navigating and transforming nested data structures and pipelines in T

Lenses are a powerful functional programming pattern that provide a first-class, composable way to "zoom in" on a specific part of a complex data structure (like a nested DataFrame or a Pipeline result) and either **view**, **set**, or **transform** it.

In T, lenses are particularly useful for:
1.  Transforming **nested DataFrames** (sub-tables created via `nest()`).
2.  Manipulating **pipeline metadata** and environment variables.
3.  Writing **generic transformations** that don't care about the specific structure of the container.

---

## 1. The Three Operations

Every lens supports three fundamental operations:

| Function | Signature | Description |
| :--- | :--- | :--- |
| **`set(data, lens, val)`** | `(A, Lens, B) -> A` | Replaces the target value with a new value. |
| **`over(data, lens, f)`** | `(A, Lens, B -> B) -> A` | Applies a function `f` to the target value and returns the updated structure. |
| **`lens.get(data)`** | `(Lens, A) -> B` | (Internal) Retrieves the current value at the lens's focus. |

---

## 2. Basic Lenses

### `col_lens(name)`
The most common lens in T. It targets a column in a DataFrame or a key in a Dictionary.

```t
employees = dataframe([
  [name: "Alice", salary: 50000],
  [name: "Bob",   salary: 60000]
])

-- 1. Get a lens for the 'salary' column
salary_l = col_lens("salary")

-- 2. Update all salaries by 10%
-- Uses T's broadcasting operator (.*) for vector updates
employees_updated = employees |> over(salary_l, \(x) x .* 1.1)

-- 3. Replace a whole column
employees_fixed = employees |> set(salary_l, [99, 99])
```

---

## 3. Composability: The `compose` Function

The true power of lenses comes from **composition**. If you have a lens for field A and a lens for field B, you can `compose(A, B)` to get a lens that targets field B *inside* field A.

### The "Killer App": Updating Nested DataFrames

Suppose you have employees nested by department. Your structure looks like this:
`department` (String) | `data` (List-Column of DataFrames)

To update the salary *inside* those nested DataFrames:

```t
-- 1. Create a lens that drills into 'data' then into 'salary'
nested_salary = compose(col_lens("data"), col_lens("salary"))

-- 2. Apply it directly to the nested structure
-- T handles the vectorization automatically!
nested |> over(nested_salary, \(x) x .* 1.1)
```

Without lenses, you would have to write complex `map` calls nested inside your transformations:
```t
-- The "Manual" Way (avoid this!)
nested |> mutate(
  $data = map($data, \(df) df |> mutate($salary = $salary * 1.1))
)
```

Lenses eliminate this "pyramid of doom" and make your data pipelines readable and declarative.

---

## 4. Orchestration Lenses: Pipelines & Environments

T is an orchestration engine, and lenses are first-class citizens for manipulating your pipeline's state before building it.

### `node_lens(node_name)`
Targets the cached result value of a specific node in a Pipeline.

### `env_var_lens(node_name, var_name)`
Targets a specific environment variable for a given node.

```t
-- Suppose we have a complex pipeline 'p'
debug_mode_l = env_var_lens("train_model", "DEBUG_VERBOSITY")

-- 1. Inject a debug flag into a specific node's environment
p_debug = p |> set(debug_mode_l, "1")

-- 2. View a specific cached node result (if it exists)
result_l = node_lens("clean_data")
data = result_l.get(p)
```

---

## 5. Summary & Best Practices

1.  **Broadcasting**: When using `over` on a column lens, the function receives a **Vector** of values (the whole column). Remember to use T's broadcasting operators (`.*`, `.+`, `.-`, `./`) to ensure element-wise updates.
2.  **Naming**: Lenses are first-class values. Name your complex composite lenses (e.g., `user_pref_theme_l`) to make your pipeline logic self-documenting.
3.  **Encapsulation**: If you are writing a reusable T module, export lenses instead of hardcoded column names. This allows users of your module to map your internal logic to their specific data schemas effortlessly.

---

## See Also
- [Data Manipulation Examples](data_manipulation_examples.html)
- [Pipeline Tutorial](pipeline_tutorial.html)
- [Quotation & Metaprogramming](quotation.html)

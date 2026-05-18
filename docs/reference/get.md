# get

Unified Data Retrieval (get)

Retrieves values from environments, collections, or pipelines using names, indices, or lenses.  This is a polymorphic primitive that unifies several retrieval modes:  1. **Variable Lookup**: `get("var_name")` retrieves a variable from the environment. 2. **Collection Indexing**: `get(collection, index)` retrieves an element (0-based). 3. **Pipeline Access**: `get(pipeline, "node_name")` retrieves a specific node result. 4. **Lens Focus**: `get(data, lens)` applies a Lens to focus on a subset of data. 5. **Default Value (Fallback)**: `get(value, default)` returns `value` unchanged when it is not NA/Error; returns `default` when `value` is NA or an Error. 6. **Safe Retrieval**: `get(target, selector, default)` performs the retrieval and returns `default` only when the result is NA (missing key/node or out-of-bounds index). Type errors in unsupported target/selector combinations propagate as errors. 7. **Cross-Node Access (Sandbox)**: `get(node_lens("name"))` retrieves a sibling node's artifact.

## Parameters

- **target** (`Any`): The environment name, Collection, Pipeline, Data, or Value to check.

- **selector** (`Any`): (Optional) The index, Node name, Lens, or Default value.

- **default** (`Any`): (Optional) The default value if the retrieval fails.


## Returns

The retrieved value or the default fallback.

## Examples

```t
salary = 50000
get("salary")                -- 50000 (Lookup)

lst = [10, 20, 30]
get(lst, 1)                  -- 20 (Indexing)

-- Safe indexing with default:
get(lst, 5, 0)               -- 0 (Index out of bounds fallback)

-- Guardrail pattern (any non-NA/Error value is returned as-is):
s = [min_age: NA]
get(s.min_age, 0) >= 0       -- true (NA falls back to 0)
get(42, 0)                   -- 42 (non-NA/Error value returned unchanged)

p = pipeline { a = 1 }
get(p, "a")                  -- 1 (Pipeline Access)
get(p, "missing", "N/A")     -- "N/A" (Safe Pipeline Access)

l = col_lens("mpg")
get(mtcars, l)               -- Vector of 'mpg' column (Lens)

-- Sandbox access (within a Nix-built node):
get(node_lens("node_a"))      -- Deserializes T_NODE_node_a artifact

```


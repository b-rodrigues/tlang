# get

Unified data retrieval for names, collections, pipelines, and lenses

`get()` is a polymorphic retrieval helper:

- `get("x")` / `get(sym("x"))` looks up a variable in the current environment
- `get(collection, index)` indexes a `List`, `Vector`, or `NDArray`
- `get(pipeline, "node")` retrieves a pipeline node result
- `get(data, lens)` applies a lens focus to a value
- `get(node_lens("name"))` retrieves a sandboxed sibling-node artifact via `T_NODE_<name>`

## Parameters

- **target** (`String | Symbol | List | Vector | NDArray | Pipeline | Lens`): The value or name to retrieve from.

- **selector** (`Int | String | Symbol | Lens`, optional): The index, node name, or lens to apply when a second argument is provided.


## Returns

The looked-up value, selected element, node result, or lens focus.

## Examples

```t
salary = 50000
get("salary")                  -- 50000
get(sym("salary"))             -- 50000

get([10, 20, 30], 1)           -- 20

p = pipeline { a = 1 }
get(p, "a")                    -- 1

l = col_lens("mpg")
get(mtcars, l)                 -- focused column

get(node_lens("model"))        -- sandbox artifact lookup
```

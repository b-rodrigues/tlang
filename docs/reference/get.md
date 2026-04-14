# get

Get variable or element

If called with one argument, retrieves a variable's value from the environment by name (String or Symbol). Matches R's `get()` semantics for variable lookup.  If called with two arguments, retrieves an element from a List, Vector, or NDArray at the specified index (0-based).

## Parameters

- **x** (`String`): | Symbol | List | Vector | NDArray The variable name or collection.

- **index** (`Int`): (Optional) The index to retrieve if `x` is a collection.


## Returns

The variable value or collection element.

## Examples

```t
salary = 50000
get("salary")
-- Returns = 50000

col_name = "salary"
get(sym(col_name))
-- Returns = 50000

get([10, 20, 30], 1)
-- Returns = 20
```


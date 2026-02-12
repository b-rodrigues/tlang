# core

Core utilities: printing, type inspection, data structures.

## Functions

| Function | Description |
|----------|-------------|
| `print(x)` | Print a value to stdout |
| `type(x)` | Return the type name of a value |
| `length(x)` | Return the length of a list, vector, or string |
| `head(x, n)` | Return the first n elements (default 6) |
| `tail(x, n)` | Return the last n elements (default 6) |
| `is_error(x)` | Check if a value is an Error |
| `seq(from, to)` | Generate an integer sequence |
| `map(list, fn)` | Apply a function to each element |
| `sum(list)` | Sum numeric elements |
| `pretty_print(x)` | Pretty-print a value with formatting |

## Examples

```t
print("Hello, world!")
type(42)              -- "Int"
length([1, 2, 3])     -- 3
head([1, 2, 3, 4], 2) -- [1, 2]
seq(1, 5)             -- [1, 2, 3, 4, 5]
sum([1, 2, 3])        -- 6
```

## Status

Built-in package — included with T by default.

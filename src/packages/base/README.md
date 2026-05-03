# base

Assertions, NA handling, and error utilities.

## Functions

| Function | Description |
|----------|-------------|
| `assert(condition)` | Assert a condition is true; error on false |
| `is_na(x)` | Check if a value is NA |
| `na()` | Generic NA value |
| `na_int()` | Integer NA value |
| `na_float()` | Float NA value |
| `na_bool()` | Boolean NA value |
| `na_string()` | String NA value |
| `error(message)` | Create a structured error value |
| `error_code(err)` | Extract the error code from an error |
| `error_message(err)` | Extract the message from an error |
| `error_context(err)` | Extract the context from an error |
| `serialize(val, path)` | Serialize a value to a `.tobj` file |
| `deserialize(path)` | Deserialize a value from a `.tobj` file |
| `t_write_json(val, path)` | Write a value to a JSON file |
| `t_read_json(path)` | Read a value from a JSON file |

## Examples

```t
assert(1 + 1 == 2)
is_na(na())           -- true
is_na(42)             -- false
error("something went wrong")
```

## Status

Built-in package — included with T by default.

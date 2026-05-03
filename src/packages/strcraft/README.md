# strcraft

Modern string manipulation utilities, inspired by R's `stringr`.

## Functions

| Function | Description |
|----------|-------------|
| `str_replace(s, p, r)` | Replace first occurrence of pattern |
| `str_replace_all(s, p, r)` | Replace all occurrences |
| `str_detect(s, p)` | Check if pattern exists |
| `str_extract(s, p)` | Extract first match |
| `str_extract_all(s, p)` | Extract all matches |
| `str_count(s, p)` | Count occurrences |
| `str_nchar(s)` | Count characters |
| `str_trim(s)` | Remove whitespace |
| `str_lines(s)` | Split into lines |
| `str_words(s)` | Split into words |
| `str_split(s, sep)` | Split by separator |
| `str_pad(s, w, side)` | Pad to width |
| `str_trunc(s, w, side)` | Truncate with ellipsis |
| `str_flatten(v, coll)` | Combine into one string |
| `to_lower(s)` / `to_upper(s)` | Case conversion |
| `str_glue(...)` | Interpolate expressions |
| `str_sprintf(fmt, ...)` | C-style formatting |

## Examples

```t
str_glue("Hello {name}")
str_replace("hello", "h", "H")
str_split("a,b,c", ",")      -- ["a", "b", "c"]
```

## Status

Built-in package — included with T by default.

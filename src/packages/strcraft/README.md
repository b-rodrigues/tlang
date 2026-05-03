# strcraft

Modern string manipulation utilities, inspired by R's `stringr`.

## Functions

| Function | Description |
|----------|-------------|
| `str_replace(s, p, r)` | Replace all occurrences of pattern (global replace) |
| `replace_first(s, p, r)` | Replace only the first occurrence of pattern |
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
| `str_flatten(values, collapse = "")` | Combine into one string with optional separator |
| `str_join(items, sep = "")` | Join items with separator |
| `to_lower(s)` / `to_upper(s)` | Case conversion |
| `str_format(fmt, values)` | Template string formatting with `{name}` placeholders |
| `str_sprintf(fmt, ...)` | C-style formatting with `%s`, `%d`, etc. |

## Examples

```t
str_sprintf("Hello %s", "world")
str_replace("hello world", "world", "T")
str_split("a,b,c", ",")      -- ["a", "b", "c"]
```

## Status

Built-in package — included with T by default.

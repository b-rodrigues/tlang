# String Manipulation in T

This guide explains how string manipulation functions are named in T, when the `str_` prefix is used, and which related helpers intentionally keep their original names.

---

## The Basic Rule

String transformation and formatting functions in T use the `str_` prefix.

This makes it easier to distinguish them from:

- generic helpers in other packages,
- functions that have non-string behavior,
- selection helpers used in data manipulation.

Examples:

```t
str_nchar("hello")          -- 5
str_substring("hello", 1, 4) -- "ell"
str_replace("banana", "a", "o") -- "bonono"
str_trim("  hello  ")       -- "hello"
str_join(["a", "b", "c"], "-") -- "a-b-c"
str_string(42)               -- "42"
str_split("a,b,c", ",")    -- ["a", "b", "c"]
```

---

## Functions That Use `str_`

The shorter string-focused helpers follow this naming convention:

- `str_nchar()`
- `str_substring()`
- `str_replace()`
- `str_trim()`
- `str_lines()`
- `str_words()`
- `str_sprintf()`
- `str_join()`
- `str_string()`
- `str_split()`

The `strsplit()` name was normalized to `str_split()` to match the rest of the string API.

---

## Why Some Names Stay Unchanged

Not every string-related helper is renamed.

Some functions deliberately keep their original names because they are already descriptive, are shared with another subsystem, or would become awkward if prefixed.

Examples that remain unchanged include:

- `contains()`
- `starts_with()`
- `ends_with()`
- `replace_first()`
- `trim_start()`
- `trim_end()`
- `char_at()`
- `index_of()`
- `last_index_of()`
- `to_lower()`
- `to_upper()`
- `is_empty()`
- `slice()`

In particular, `contains()`, `starts_with()`, and `ends_with()` are also used as column-selection helpers in `colcraft`, so keeping those names makes the data-manipulation API more consistent.

---

## Common Patterns

### Inspecting strings

```t
str_nchar("hello")
is_empty("")
contains("tlang", "lang")
starts_with("prefix", "pre")
ends_with("suffix", "fix")
```

### Extracting and modifying text

```t
str_substring("abcdef", 1, 4)
char_at("abcdef", 2)
str_replace("banana", "a", "o")
replace_first("banana", "a", "o")
```

### Cleaning and splitting text

```t
str_trim("  hello  ")
trim_start("  hello  ")
trim_end("  hello  ")
str_lines("a\nb\nc")
str_words("hello   world")
str_split("a,b,c", ",")
```

### Formatting and conversion

```t
str_sprintf("Hello, %s!", "world")
str_join(["red", "green", "blue"], ", ")
str_string(3.14)
```

---

## Selection Helpers vs String Helpers

When working with DataFrames, some names such as `starts_with()` and `contains()` can be used for column selection:

```t
df |> select(starts_with("petal"))
df |> select(contains("width"))
```

When called with string arguments, the same names still behave as string predicates:

```t
starts_with("petal_width", "petal")
contains("petal_width", "width")
```

That is why these names are intentionally left without the `str_` prefix.

---

## Related Reference Pages

For per-function details, see the reference pages:

- [`str_nchar`](reference/nchar.html)
- [`str_substring`](reference/substring.html)
- [`str_replace`](reference/replace.html)
- [`str_sprintf`](reference/sprintf.html)
- [`str_join`](reference/join.html)
- [`str_string`](reference/string.html)
- [`str_split`](reference/strsplit.html)
- [`contains`](reference/contains.html)
- [`starts_with`](reference/starts_with.html)
- [`ends_with`](reference/ends_with.html)

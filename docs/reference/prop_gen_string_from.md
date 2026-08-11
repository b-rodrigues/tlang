# prop_gen_string_from

Generate a random String

Returns a generator spec producing Strings whose characters are drawn from `chars` (a String, List, or Vector of Strings) with lengths between `min_len` and `max_len` inclusive.

## Parameters

- **chars** (`String|List[String]`): Candidate characters.

- **min_len** (`Int`): Minimum length (inclusive).

- **max_len** (`Int`): Maximum length (inclusive).


## Returns

A generator spec.

## Examples

```t
assert(prop_for_all(prop_gen_string_from("ab", 1, 3), \(s) length(s) <= 3))
```

## See Also

[prop_gen_int](prop_gen_int.html)


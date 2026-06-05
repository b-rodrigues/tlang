# fct_other

Replace unlisted levels with Other

Keeps selected factor levels and maps the rest to an "Other" bucket.

## Parameters

- **x** (`Vector[Factor]`): A factor vector.

- **keep** (`Vector[String]`): | List[String] Levels to preserve.

- **drop** (`Vector[String]`): | List[String] Levels to drop (mutually exclusive with keep).

- **other_level** (`String`): = "Other" Name for the catch-all level.


## Returns

A factor vector with unlisted levels replaced.

## Examples

```t
fct_other(fct, keep = ["a", "b"])
fct_other(fct, drop = ["z"], other_level = "Misc")
```


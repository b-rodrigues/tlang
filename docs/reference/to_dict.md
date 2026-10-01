# to_dict

Convert record to Dict

Converts a user-defined record to a plain Dict with one entry per field, so record data can cross into foreign node code (records themselves are T-side contracts and never cross). Shallow: nested records stay records; call `to_dict` on them first if needed.

## Parameters

- **x** (`Record`): The record to convert.


## Returns

A Dict mapping field names to values.

## Examples

```t
to_dict(Point(x = 1.0, y = 2.0))
```


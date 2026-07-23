# expect_has_colnames

DataFrame / Dict subset column names assertion

Passes if the DataFrame, Dict, or named List contains at least all of the expected column/field names. Order is not required, and additional columns/fields are permitted.

## Parameters

- **data** (`DataFrame`): | Dict | List The container to check.

- **names** (`String`): | List | Vector The required column/field name or list/vector of required names.


## Returns

`Expect_pass` when all expected columns exist; `Expect_hold` on NA; `Expect_stop` on missing columns.

## Examples

```t
assert(expect_has_colnames(to_dataframe([x: [1], y = [2]]), ["x"]))
assert(expect_has_colnames(to_dataframe([x: [1], y = [2]]), "y"))
```

## See Also

[expect_ncol](expect_ncol.html), [expect_nrow](expect_nrow.html), [expect_fields](expect_fields.html), [expect_colnames](expect_colnames.html)


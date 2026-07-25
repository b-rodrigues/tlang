# expect_summary

Expectation test suite summary report

Summarizes a List or Dict of Expect values / check results into a DataFrame report table.

## Parameters

- **checks** (`Dict`): | List A dictionary or list of expectation check results.


## Returns

A DataFrame with columns `check`, `status`, and `message`.

## Examples

```t
summary_df = expect_summary([c1: expect_equal(1, 1), c2 = expect_equal(2, 2)])
```

## See Also

[expect_fail](expect_fail.html), [expect_pass](expect_pass.html)


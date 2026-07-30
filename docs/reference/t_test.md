# t_test

Run tests

Runs the test suite for the current package and returns a DataFrame with results. Wraps the CLI `t test` command for use within the REPL.

## Parameters

- **only** (`List`): = [] Filter to tests whose path contains any of these substrings.

- **not** (`List`): = [] Exclude tests whose path contains any of these substrings.


## Returns

A DataFrame with columns: file, status, duration_ms, error.

## Examples

```t
results = t_test()
results |> filter($status == "failed")
results = t_test(only = ["arithmetic"])
results = t_test(not = ["slow"])
```


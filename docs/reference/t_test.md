# t_test

Run tests

Runs the test suite for the current package and returns a DataFrame with results. Wraps the CLI `t test` command for use within the REPL.

## Parameters

- **only** (`List`): = [] Filter to tests whose path contains any of these substrings.

- **not** (`List`): = [] Exclude tests whose path contains any of these substrings.

- **failfast** (`Bool`): = false Stop after the first failing test file.

- **timeout** (`Float`): = NA Mark any test exceeding this many seconds as failed (test file body only; shared src/ setup is excluded).

- **verbose** (`Bool`): = false Print per-file error details.


## Returns

A DataFrame with columns: file, status, duration_ms, error.

## Examples

```t
results = t_test()
results |> filter($status == "failed")
results = t_test(only = ["arithmetic"])
results = t_test(not = ["slow"])
results = t_test(failfast = true, timeout = 30, verbose = true)
```


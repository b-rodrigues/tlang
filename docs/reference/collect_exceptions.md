# collect_exceptions

Gather Pipeline Node Exceptions and Warnings

Gathers all `VError` values and warning diagnostics from computed nodes of a built pipeline and returns them as a structured DataFrame.

## Parameters

- **pipeline** (`Pipeline`): The built pipeline to gather exceptions from.


## Returns

A DataFrame with columns `node`, `status`, `code`, and `message`.


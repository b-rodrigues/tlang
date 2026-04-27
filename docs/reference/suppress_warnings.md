# suppress_warnings

Suppress Diagnostics for a Node

Silences all captured warnings for the current node in the console summary. Warnings remain accessible programmatically via `read_node()` or `read_pipeline()`. Use this to reduce noise from known warnings during data processing (e.g., NAs in filter).

## Parameters

- **value** (`Any`): The value or expression to wrap. Usually call it at the end of a node definition.


## Returns

The original value, signaling the evaluator to suppress diagnostic output.


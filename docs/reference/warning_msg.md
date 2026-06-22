# warning_msg

Get warning message

Returns the human-readable warning associated with a completed computed node, or an empty string if none. Upstream warnings inherited from ancestor nodes are prefixed with the source node name for clear provenance. Multiple warnings are joined with ". Furthermore, ".

## Parameters

- **node** (`ComputedNode`): The computed node to inspect.


## Returns

The formatted warning message, or "" if no warnings.


# is_failed

Test if a node failed

Returns true for a failed node (VError), for a `read_node()` result whose value or diagnostics carry an error, or for an inspect result with status Errored or SoftFailed. Use this after 0.56.1 instead of is_error(inspect_node(x)), which is always false. NA propagates as NA; a value that is not a node, read_node result, inspect result, or error is false.

## Parameters

- **node** (`Any`): A node value, read_node result, inspect result, or error.


## Returns

True when failed or Errored.


# warning_msg

Get warning message

Returns the human-readable warning associated with a completed computed node, or an empty string if none. For downstream nodes that inherit warnings from ancestor nodes, each warning is prefixed with its source to make provenance clear.

## Parameters

- **node** (`ComputedNode`): The computed node to inspect.


## Returns

The warning message string. Format depends on the warning source:

- **Own warning**: The raw warning message (e.g. `"filter() excluded 1 row because the predicate evaluated to NA"`).
- **Upstream warning**: Prefixed with `"Ancestor node '<name>' reported following warning: <message>"`.
- **Multiple warnings** (own + upstream, or multiple upstream): Joined with `". Furthermore, "`.

### Examples

Node with only an own warning:
```t
warning_msg(p.filtered)
-- "filter() excluded 1 row because the predicate evaluated to NA"
```

Downstream node that inherits a warning from an ancestor:
```t
warning_msg(p.count)
-- "Ancestor node 'filtered' reported following warning: filter() excluded 1 row because the predicate evaluated to NA"
```

Node with both an own warning and inherited upstream warnings:
```t
warning_msg(p.summary)
-- "mutate() created NAs. Furthermore, Ancestor node 'filtered' reported following warning: filter() excluded 1 row because the predicate evaluated to NA"
```


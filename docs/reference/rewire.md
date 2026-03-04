# rewire

Rewire a Node's Dependencies

Reroutes a node's declared dependencies. The `replace` argument is a named list (or Dict) mapping old dependency names to new ones. Only the named node's dependency list is updated.

## Parameters

- **p** (`Pipeline`): The pipeline.
- **name** (`String`): The name of the node whose deps should change.
- **replace** (`List[String]`): A named list mapping old dep names to new ones.

## Returns:

Returns: A new pipeline with updated dependency edges.

## Examples

```t
p |> rewire("model_py", replace = list(data = "data_v2"))
```

## See Also

[rename_node](rename_node.html), [swap](swap.html)


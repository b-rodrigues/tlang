# swap

Swap a Pipeline Node Implementation

Replaces a node's implementation with a new node value. The dependency edges of the replaced node are preserved — this operation only changes the node's command and metadata. Use `rewire` to change dependencies.

## Parameters

- **p** (`Pipeline`): The pipeline.
- **name** (`String`): The name of the node to replace.
- **new_node** (`Node`): The new node implementation.

## Returns:

Returns: A new pipeline with the node replaced.

## Examples

```t
p |> swap("model_r", node(command = <{ lm(y ~ x, data) }>, runtime = R))
```

## See Also

[patch](patch.html), [rename_node](rename_node.html), [rewire](rewire.html)


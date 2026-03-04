# filter_node

Filter Pipeline Nodes

Returns a new pipeline containing only the nodes for which the predicate returns `true`. Uses NSE (`$field`) to refer to node metadata fields.  No DAG validity check is performed. If a retained node depends on a node that was removed, that inconsistency surfaces only at `build_pipeline` or `pipeline_run`.  Supported metadata fields: `$name`, `$runtime`, `$serializer`, `$deserializer`, `$noop`, `$depth`, `$command_type`.

## Parameters

- **p** (`Pipeline`): The pipeline to filter.
- **predicate** (`Function`): A predicate function returning Bool for each node.

## Returns:

Returns: A new pipeline with only the matching nodes.

## Examples

```t
p |> filter_node($runtime == "python")
p |> filter_node($noop == false)
p |> filter_node($depth <= 2)
```

## See Also

[rename_node](rename_node.md), [select_node](select_node.md), [mutate_node](mutate_node.md)


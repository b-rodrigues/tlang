# mutate_node

Mutate Pipeline Node Metadata

Modifies metadata fields on pipeline nodes. Supports a `where` named argument to scope changes to a subset of nodes. Without `where`, all nodes are affected.  Mutable metadata fields: `noop` (Bool), `serializer` (String), `deserializer` (String), `runtime` (String).  The `where` clause uses NSE (`$field`) just like `filter_node`.

## Parameters

- **p** (`Pipeline`): The pipeline to modify.
- **...** (`KeywordArgs`): Metadata assignments as `$field = value` pairs.
- **where** (`Function`): (Optional) Predicate scoping which nodes are updated.

## Returns:

Returns: A new pipeline with updated node metadata.

## Examples

```t
p |> mutate_node($noop = true)
p |> mutate_node($serializer = "pmml", where = $runtime == "R")
```

## See Also

[rename_node](rename_node.md), [filter_node](filter_node.md)


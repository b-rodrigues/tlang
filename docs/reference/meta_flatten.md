# meta_flatten

Flatten MetaPipeline into Standard Pipeline

Takes a MetaPipeline or standard Pipeline and flattens it, resolving all nested namespace relationships (such as dotted node references) into a single flat dependency graph pipeline.

## Parameters

- **mp** (`MetaPipeline|Pipeline`): The metapipeline or pipeline to flatten.


## Returns

The flattened standard pipeline.

## Examples

```t
meta_flatten(mp)
```


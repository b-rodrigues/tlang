# custom

Quote a custom strategy function name

Strategies are a closed set: `default`, `^csv`, `^json`, `^ipc`, `^parquet`, `^pmml`, `^onnx`, `^bin`, `^text`, and `^tlang`. A bare name outside that set is rejected where a strategy is expected. Quote a custom reader/writer with `custom("name")` and declare it in the node's `functions` files; it resolves against those files at build time.

## Parameters

- **name** (`String`): The custom reader/writer function name.


## Returns

The quoted name, usable in `serializer` and `deserializer` positions.

## Examples

```t
node(serializer = custom("write_pkl"), functions = ["my_serializer.py"])
```

## See Also

[node](node.html)


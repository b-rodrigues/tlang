# emit_node

Node Emitter

Generates a Nix derivation for a single pipeline node.

## Parameters

- **(name,**: expr) :: (String, Expression) The node name and its expression.
- **deps** (`List[String]`): Names of nodes this node depends on.
- **import_lines** (`List[String]`): Import statements to prepend to the script.

## Returns

A string containing the Nix derivation code.


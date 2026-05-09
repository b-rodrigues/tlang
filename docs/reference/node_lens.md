# node_lens

Pipeline Node Lens

Targets the cached result value of a specific node in a Pipeline. In a Nix-managed sandbox, this lens also supports cross-node retrieval using the 1-argument `get(node_lens("name"))` syntax, which automatically locates and deserializes the sibling node's artifact from the environment.

## Parameters

- **node_name** (`String`): The name of the node.


## Returns

A lens for the node's value.


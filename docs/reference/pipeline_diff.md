# pipeline_diff

Compare Pipeline Structures

Compares two `Pipeline` values and returns a structured diff describing which nodes were added, removed, changed, or rewired.  Unlike `node_diff`, which compares node artifacts across builds, `pipeline_diff` compares in-memory pipeline structure.

## Parameters

- **p_a** (`Pipeline`): The "before" pipeline.

- **p_b** (`Pipeline`): The "after" pipeline.


## Returns

A structural diff dictionary.


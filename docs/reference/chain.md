# chain

Chain Two Pipelines

Connects two pipelines by merging them. The second pipeline can reference node names from the first pipeline as dependencies — these are automatically satisfied. Errors if there are name collisions (other than the intentional inter-pipeline wiring) or if no shared names exist between the two pipelines.

## Parameters

- **p1** (`Pipeline`): The upstream pipeline (provides outputs).

- **p2** (`Pipeline`): The downstream pipeline (consumes inputs).


## Returns

A merged pipeline with p2's nodes wired to p1's outputs.

## Examples

```t
p_etl |> chain(p_model)
```

## See Also

[union](union.html), [parallel](parallel.html)


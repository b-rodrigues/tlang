-- examples/polyglot_pipeline.t
-- A comprehensive demonstration of T's polyglot orchestration.
-- This pipeline coordinates T, R, and Python runtimes.

print("=== T Polyglot Pipeline Demo ===")

p = pipeline {
  -- 1. Native T node: filter data
  -- Uses the sales.csv file in the examples directory
  data = node(
    command = read_csv("examples/sales.csv") |> filter($amount > 100),
    serializer = "arrow"
  )

  -- 2. R node: train a model
  -- PMML is used for cross-language model serialization
  model_r = rn(
    command = <{
      lm(amount ~ category, data = data)
    }>,
    serializer = "pmml",
    deserializer = "arrow"
  )

  -- 3. Python node: execute an external script
  -- Uses the score.py script in the examples directory
  scored = pyn(
    script = "examples/score.py",
    deserializer = "pmml",
    serializer = "json"
  )
}

-- In a real workflow, you would build the pipeline to run it in the Nix sandbox:
build_pipeline(p)

-- For this demo, we can inspect the pipeline structure:
print("Nodes in pipeline:")
print(pipeline_nodes(p))

print("Pipeline definition verified. To execute, run with: t build_pipeline(p)")
print("Note: Execution requires R and Python runtimes available via Nix.")

print("=== Demo definition complete ===")

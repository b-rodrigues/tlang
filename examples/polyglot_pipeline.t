-- examples/polyglot_pipeline.t
-- A comprehensive demonstration of T's polyglot orchestration.
-- This pipeline coordinates T, R, and Python runtimes.

print("=== T Polyglot Pipeline Demo ===")

p = pipeline {
  -- 1. Load data natively in T (CSV backend)
  data = node(
    command = read_csv("examples/sales.csv") |> filter($amount > 100),
    serializer = "arrow"
  )

  -- 2. Train a statistical model in R (using the rn() wrapper)
  -- PMML is used for cross-language model serialization
  model_r = rn(
    command = <{
      lm(amount ~ category, data = data)
    }>,
    serializer = "pmml",
    deserializer = "arrow"
  )

  -- 3. Predict natively in T (no R/Python runtime needed for evaluation!)
  predictions = node(
    command = data |> mutate($pred = predict(data, model_r)),
    deserializer = "pmml"
  )

  -- 4. Generate a shell report
  report = shn(command = <{
    printf 'R model results cached at: %s\n' "$T_NODE_model_r/artifact"
  }>)
}

-- In a real workflow, you would build the pipeline to run it in the Nix sandbox:
-- build_pipeline(p)

-- For this demo, we can inspect the pipeline structure:
print("Nodes in pipeline:")
print(pipeline_nodes(p))

print("Pipeline definition verified. To execute, run with: t build_pipeline(p)")
print("Note: Execution requires R and Python runtimes available via Nix.")

print("=== Demo definition complete ===")

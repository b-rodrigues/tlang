-- examples/pipeline_example.t
-- End-to-end pipeline example for T alpha
-- Demonstrates: pipeline definition, dependency resolution, introspection

print("=== T Pipeline Example ===")
print("")

-- Define a computation pipeline
print("Step 1: Define pipeline")
p = pipeline {
  data = [10, 20, 30, 40, 50]
  doubled = map(data, \(x) x * 2)
  total = sum(doubled)
  count = length(data)
  average = total / count
}

print("Pipeline created:")
print(p)
print("")

-- Access individual nodes
print("Step 2: Access nodes")
print("Data:")
print(p.data)
print("Doubled:")
print(p.doubled)
print("Total:")
print(p.total)
print("Count:")
print(p.count)
print("Average:")
print(p.average)
print("")

-- Introspect the pipeline
print("Step 3: Pipeline introspection")
print("Nodes:")
print(pipeline_nodes(p))
print("Dependencies:")
print(pipeline_deps(p))
print("")

-- Re-run and verify determinism
print("Step 4: Re-run pipeline")
p2 = pipeline_run(p)
assert(p.total == p2.total, "Pipeline re-run should produce same results")
print("Re-run produces identical results: true")
print("")

-- Pipeline with out-of-order dependencies
print("Step 5: Out-of-order dependencies")
p3 = pipeline {
  result = a + b + c
  a = 100
  b = 200
  c = 300
}
print("Result (declared before dependencies):")
print(p3.result)
assert(p3.result == 600)
print("")

-- Explain a pipeline
print("Step 6: Pipeline explain")
e = explain(p)
print("Kind:")
print(e.kind)
print("Node count:")
print(e.node_count)
print("")

print("=== Pipeline Example Complete ===")

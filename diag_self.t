
-- Diagnostics for Pipeline Self-Access

p = pipeline {
  node_a = 100
  dynamic_access = get(self, node_lens("node_a"))
}

print("Pipeline results:")
print(p.node_a)
print(p.dynamic_access)

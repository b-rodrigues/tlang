
-- Diagnostics for Lambda nodes

p = pipeline {
  node_a = 100
  dynamic_access = \(p_self) {
    target = "node_a"
    get(p_self, node_lens(target))
  }
}

-- Locally, p.dynamic_access might keep being a lambda
print("dynamic_access value:")
print(p.dynamic_access)
-- If we call it
print("dynamic_access called with p:")
print(p.dynamic_access(p))

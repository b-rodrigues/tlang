p = pipeline {
    node_a = 1
    node_b = 2
    
    dynamic_access = \(p_self: Pipeline) {
      target = "node_a"
      get(p_self, node_lens(target))
    }
  }

-- print(p$dynamic_access)
-- print(get(p, "node_a"))

-- Manual diagnostics
print("Dynamic access result:")
print(p.dynamic_access)

print("Direct get(p, \"node_a\") result:")
print(get(p, "node_a"))

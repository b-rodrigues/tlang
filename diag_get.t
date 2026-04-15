
-- Diagnostics for Unified get()

-- 1. Variable lookup
salary = 50000
print("Lookup salary:")
print(get("salary"))
print(get(sym("salary")))

-- 2. Collection Indexing
lst = [10, 20, 30]
print("Index list:")
print(get(lst, 1))

-- 3. Pipeline Node Lookup (Direct)
p = pipeline {
  node_a = 1 + 1
  node_b = node_a * 10
}
print("Pipeline Node lookup node_a (direct):")
print(get(p, "node_a"))

-- 4. Lens Focus (Node Lens)
l = node_lens("node_a")
print("Lens get node_a from pipeline (node_lens):")
print(get(p, l))

-- 5. Composition
-- (Using Dict literal [key: value])
data = [a: [b: 42]]
print("Data structure:")
print(data)
l_comp = compose(col_lens("a"), col_lens("b"))
print("Composite lens get:")
print(get(data, l_comp))

-- Test Case 5: Pipeline Inspection & Lenses (Corrected DF syntax)

p = pipeline {
  a = node(command = 1)
  b = node(command = error("Failure in b"))
  c = node(command = a + 1)
}

-- 1. Build so we have logs
res_path = populate_pipeline(p, build = true)
print("Build output path:", res_path)

-- 2. Test which_nodes
err_nodes = which_nodes(p, \(n) !is_na(n.diagnostics.error))
print("Errored nodes (name only):", map(err_nodes, \(n) n.name))

-- 3. Test filter_node
sub = filter_node(p, !is_na($diagnostics.error))
print("Filtered pipeline nodes:", pipeline_nodes(sub))

-- 4. Test Lenses (col_lens)
my_dict = [a: 10, b: 20]
l = col_lens("a")
val = get(my_dict, l)
print("Lens access (get with col_lens):", val)

-- 5. Test idx_lens
my_list = [100, 200, 300]
il = idx_lens(1)
print("Index lens access:", get(my_list, il))

-- 6. Test row_lens on a DataFrame
-- Use correct Dictionary syntax for column-wise construction
df = dataframe([a: [1, 2], b: [3, 4]])
rl = row_lens(1)
print("Row lens access (row 1):", get(df, rl))

print("Test Case 5 passed!")

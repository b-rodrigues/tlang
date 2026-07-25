-- Check Scalar Logic
assert((true && false) == false, "Scalar && failed")
assert((true || false) == true, "Scalar || failed")
assert((!true) == false, "Scalar ! failed")

v1 = [true, false, true, false]
v2 = [true, true, false, false]

-- Vector logic operations
v_and = v1 .& v2
v_or = v1 .| v2
v_not = map(v1, \(x) !x)

result = to_dataframe([
  [v1: v1, v2: v2, v_and: v_and, v_or: v_or, v_not: v_not]
])
write_csv(result, "tests/golden/t_outputs/logical_ops.csv")

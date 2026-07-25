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

assert(identical(v_and, [true, false, false, false]), "Vector .& failed")
assert(identical(v_or, [true, true, true, false]), "Vector .| failed")
assert(identical(v_not, [false, true, false, true]), "Vector ! failed")

result = to_dataframe([
  [v1: true,  v2: true,  v_and: true,  v_or: true,  v_not: false],
  [v1: false, v2: true,  v_and: false, v_or: true,  v_not: true],
  [v1: true,  v2: false, v_and: false, v_or: true,  v_not: false],
  [v1: false, v2: false, v_and: false, v_or: false, v_not: true]
])
write_csv(result, "tests/golden/t_outputs/logical_ops.csv")

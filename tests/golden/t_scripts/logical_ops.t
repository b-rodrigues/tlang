-- Check Scalar Logic
print("Checking Scalar Logic...")
assert((true && false) == false, "Scalar && failed")
assert((true || false) == true, "Scalar || failed")
print("Scalar !:")
print(!true)

v1 = [true, false, true, false]
v2 = [true, true, false, false]

-- Check Vector Logic (Broadcast)
print("Checking Vector Logic...")
v_and = v1 .& v2
expected_and = [true, false, false, false]
assert(v_and == expected_and, "Vector .& failed")

v_or = v1 .| v2
expected_or = [true, true, true, false]
assert(v_or == expected_or, "Vector .| failed")

print("✓ logical_ops complete")

v1 = [true, false, true, false]
v2 = [true, true, false, false]
v_and = v1 .& v2
expected_and = [true, false, false, false]
print("v_and:", v_and)
print("expected_and:", expected_and)
print("v_and == expected_and:", v_and == expected_and)

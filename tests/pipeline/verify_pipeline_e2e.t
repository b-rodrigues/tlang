-- Pipeline Integration Test — Verification Script
--
-- Run with --unsafe (no build_pipeline call needed).
-- Verifies that the pipeline infrastructure produced correct artifacts.

-- 1. Check that build logs exist
logs = inspect_pipeline()
assert(length(logs) > 0, "Expected at least one build log")
print(paste("Found", string(length(logs)), "build log(s)"))

-- 2. Read a scalar node and verify its value
avg = read_node("avg_mpg")
assert(type(avg) == "Float", paste("avg_mpg should be Float, got", type(avg)))
-- mtcars avg mpg is ~20.09
assert(avg > 19, paste("avg_mpg should be > 19, got", string(avg)))
assert(avg < 21, paste("avg_mpg should be < 21, got", string(avg)))
print(paste("avg_mpg =", string(avg), "OK"))

-- 3. Read another scalar node
sd_val = read_node("sd_mpg")
assert(type(sd_val) == "Float", paste("sd_mpg should be Float, got", type(sd_val)))
print(paste("sd_mpg =", string(sd_val), "OK"))

-- 4. Read a DataFrame node and verify its shape
six = read_node("six_cyl")
assert(type(six) == "DataFrame", paste("six_cyl should be DataFrame, got", type(six)))
assert(nrow(six) == 7, paste("six_cyl should have 7 rows, got", string(nrow(six))))
print(paste("six_cyl: nrow =", string(nrow(six)), "OK"))

-- 5. Read the derived stat
avg_hp = read_node("avg_hp_6cyl")
assert(type(avg_hp) == "Float", paste("avg_hp_6cyl should be Float, got", type(avg_hp)))
print(paste("avg_hp_6cyl =", string(avg_hp), "OK"))

-- 6. Time-travel: read from a specific log
first_log = get(logs, 1)
print(paste("Testing time-travel with log:", first_log))
avg2 = read_node("avg_mpg", which_log=first_log)
assert(avg == avg2, "Time-travel read should match latest read")
print("Time-travel read matches — OK")

-- 7. Verify _pipeline/ structure
assert(length(logs) >= 1, "Should have at least 1 build log")
print(paste("inspect_pipeline() returned", string(length(logs)), "log(s)"))

print("\nAll pipeline integration checks passed!")

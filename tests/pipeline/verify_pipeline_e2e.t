-- Pipeline Integration Test — Verification Script
--
-- Run with --unsafe (no build_pipeline call needed).
-- Verifies that the pipeline infrastructure produced correct artifacts.

-- 1. Check that build logs exist
logs = list_pipelines()
assert(length(logs) > 0, "Expected at least one build log")
print(join(["Found", length(logs), "build log(s)"], " "))

-- 2. Read a scalar node and verify its value
avg = read_node("avg_mpg")
assert(type(avg) == "Float", join(["avg_mpg should be Float, got ", type(avg)]))
-- mtcars avg mpg is ~20.09
assert(avg > 19, join(["avg_mpg should be > 19, got ", avg]))
assert(avg < 21, join(["avg_mpg should be < 21, got ", avg]))
print(join(["avg_mpg = ", avg, " OK"]))

-- 3. Read another scalar node
sd_val = read_node("sd_mpg")
assert(type(sd_val) == "Float", join(["sd_mpg should be Float, got ", type(sd_val)]))
print(join(["sd_mpg = ", sd_val, " OK"]))

-- 4. Read a DataFrame node and verify its shape
six = read_node("six_cyl")
assert(type(six) == "DataFrame", join(["six_cyl should be DataFrame, got ", type(six)]))
assert(nrow(six) == 7, join(["six_cyl should have 7 rows, got ", nrow(six)]))
print(join(["six_cyl: nrow = ", nrow(six), " OK"]))

-- 5. Read the derived stat
avg_hp = read_node("avg_hp_6cyl")
assert(type(avg_hp) == "Float", join(["avg_hp_6cyl should be Float, got ", type(avg_hp)]))
print(join(["avg_hp_6cyl = ", avg_hp, " OK"]))

-- 6. Time-travel: read from a specific log
first_log = get(logs, 0)
print(join(["Testing time-travel with log: ", first_log]))
avg2 = read_node("avg_mpg", which_log=first_log)
assert(avg == avg2, "Time-travel read should match latest read")
print("Time-travel read matches — OK")

-- 7. Verify _pipeline/ structure
assert(length(logs) >= 1, "Should have at least 1 build log")
print(join(["list_pipelines() returned", length(logs), "log(s)"], " "))

print("\nAll pipeline integration checks passed!")

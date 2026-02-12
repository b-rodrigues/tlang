-- tests/test-test-pkg.t
-- Tests for test-pkg

-- Test: greet function
result = greet("world")
assert(result == "Hello, world!")

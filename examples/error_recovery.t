-- examples/error_recovery.t
-- Demonstrates error recovery patterns with the maybe-pipe operator ?|>

print("=== Error Recovery with Maybe-Pipe ===")
print("")

-- The key difference between |> and ?|>:
--   |>  short-circuits on error (never calls the function)
--   ?|> always forwards the value (including errors) to the function

-- Pattern 1: Provide a default value on error
print("Pattern 1: Default Value Recovery")
with_default = \(result) if (is_error(result)) 0 else result

value1 = 5 ?|> with_default
print(value1)

value2 = error("something broke") ?|> with_default
print(value2)
print("")

-- Pattern 2: Error inspection and recovery
print("Pattern 2: Error Inspection")
handle = \(x) if (is_error(x)) "recovered" else x
result = error("something broke") ?|> handle
print(result)
print("")

-- Pattern 3: Chaining recovery with normal processing
print("Pattern 3: Mixed Pipe Chain")
recovery = \(x) if (is_error(x)) 0 else x
increment = \(x) x + 1

-- ?|> forwards error to recovery, then |> continues normally
final = error("fail") ?|> recovery |> increment
print(final)
print("")

-- Pattern 4: Type checking through maybe-pipe
print("Pattern 4: Type Checking")
err = error("test")
err_type = err ?|> type
print(err_type)
is_err = err ?|> is_error
print(is_err)
print("")

-- Pattern 5: Both pipes behave the same on normal values
print("Pattern 5: Normal Values")
double = \(x) x * 2
result1 = 5 |> double
result2 = 5 ?|> double
assert(result1 == result2)
print("Both pipes produce the same result on normal values")
print("")

print("=== Examples Complete ===")

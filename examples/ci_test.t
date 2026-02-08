-- ci_test.t
-- Comprehensive test script for CI/CD
-- This script tests various features of the T language

print("=== T Language CI Test Suite ===")
print("")

-- Test 1: Basic arithmetic
print("Test 1: Basic Arithmetic")
assert(2 + 2 == 4)
assert(10 - 3 == 7)
assert(4 * 5 == 20)
assert(15 / 3 == 5)
print("✓ Arithmetic operations working")
print("")

-- Test 2: Variables and assignment
print("Test 2: Variables")
x = 42
y = 58
sum_result = x + y
assert(sum_result == 100)
print("✓ Variables and assignment working")
print("")

-- Test 3: Functions
print("Test 3: Functions")
square = \(n) n * n
assert(square(5) == 25)
assert(square(10) == 100)

add = \(a, b) a + b
assert(add(3, 7) == 10)
print("✓ Lambda functions working")
print("")

-- Test 4: Higher-order functions
print("Test 4: Higher-order Functions")
numbers = [1, 2, 3, 4, 5]
squares = map(numbers, \(x) x * x)
assert(head(squares) == 1)
assert(head(tail(squares)) == 4)
print("✓ map() function working")
print("")

-- Test 5: Pipe operator
print("Test 5: Pipe Operator")
double = \(x) x * 2
result = 5 |> double
assert(result == 10)
print("✓ Pipe operator working")
print("")

-- Test 6: Lists
print("Test 6: Lists")
my_list = [10, 20, 30]
assert(length(my_list) == 3)
assert(head(my_list) == 10)
assert(sum(my_list) == 60)
print("✓ List operations working")
print("")

-- Test 7: Conditionals
print("Test 7: Conditionals")
result = if (5 > 3) "yes" else "no"
assert(result == "yes")
result2 = if (1 > 10) "wrong" else "correct"
assert(result2 == "correct")
print("✓ If/else working")
print("")

-- Test 8: Named lists (records)
print("Test 8: Named Lists")
person = [name: "Alice", age: 30]
assert(person.name == "Alice")
assert(person.age == 30)
print("✓ Named lists working")
print("")

-- Test 9: Dictionaries
print("Test 9: Dictionaries")
config = {host: "localhost", port: 8080}
assert(config.host == "localhost")
assert(config.port == 8080)
print("✓ Dictionaries working")
print("")

-- Test 10: Closures
print("Test 10: Closures")
make_adder = \(n) \(x) x + n
add_five = make_adder(5)
assert(add_five(10) == 15)
assert(add_five(20) == 25)
print("✓ Closures working")
print("")

-- Test 11: seq function
print("Test 11: seq Function")
range = seq(1, 5)
assert(length(range) == 5)
assert(head(range) == 1)
print("✓ seq() working")
print("")

-- Test 12: Complex pipe chain
print("Test 12: Complex Pipe Chain")
final = [1, 2, 3, 4, 5]
  |> map(\(x) x * x)
  |> sum
assert(final == 55)  -- 1 + 4 + 9 + 16 + 25 = 55
print("✓ Complex pipe chains working")
print("")

-- Test 13: Boolean operations
print("Test 13: Boolean Operations")
assert(true and true == true)
assert(true and false == false)
assert(false or true == true)
assert(not false == true)
assert(not true == false)
print("✓ Boolean operations working")
print("")

-- Test 14: Comparison operators
print("Test 14: Comparison Operators")
assert(5 > 3)
assert(3 < 5)
assert(5 >= 5)
assert(5 <= 5)
assert(5 == 5)
assert(5 != 3)
print("✓ Comparison operators working")
print("")

-- Test 15: Error handling
print("Test 15: Error Handling")
error_result = 1 / 0
assert(is_error(error_result))
valid_result = 10 / 2
assert(not is_error(valid_result))
print("✓ Error handling working")
print("")

-- Test 16: Type introspection
print("Test 16: Type Introspection")
assert(type(42) == "Int")
assert(type("hello") == "String")
assert(type(true) == "Bool")
assert(type([1, 2, 3]) == "List")
assert(type({x: 1}) == "Dict")
print("✓ Type introspection working")
print("")

print("=== All Tests Passed! ===")
print("T language is working correctly.")

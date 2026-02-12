# Custom Nominal Types with Mandatory Validation

**Status**: Draft  
**Version**: 0.1  
**Target Release**: Beta  
**Author**: Implementation Team  
**Date**: 2026-02-12

---

## Table of Contents

1. [Overview](#overview)
2. [Motivation](#motivation)
3. [Design Principles](#design-principles)
4. [Language Syntax](#language-syntax)
5. [Type System Integration](#type-system-integration)
6. [Semantic Rules](#semantic-rules)
7. [Runtime Behavior](#runtime-behavior)
8. [Error Handling](#error-handling)
9. [Pattern Matching](#pattern-matching)
10. [Examples](#examples)
11. [Implementation Phases](#implementation-phases)
12. [Testing Strategy](#testing-strategy)
13. [Open Questions](#open-questions)

---

## Overview

This document specifies the implementation of **custom nominal types with mandatory validation** for the T programming language. This feature allows users to define domain-specific data types with compile-time enforced validation, maintaining T's core philosophy of explicitness, safety, and reproducibility.

### Key Features

- **Nominal typing**: Types are distinct by declaration, not structure
- **Mandatory validation**: Every type definition requires a validator block
- **Explicit error handling**: All construction returns `Result<T, E>` types
- **No bypass**: Direct construction is prohibited by the compiler
- **Sum types**: Support for tagged unions with per-variant validation
- **Visible structure**: All fields remain accessible after validation
- **Pattern matching**: Full integration with T's existing pattern matching

---

## Motivation

### Current Limitations

T currently lacks user-defined types beyond primitive types (int, float, string, bool), vectors, and dataframes. Users cannot:

1. Define domain-specific types (e.g., `Date`, `EmailAddress`, `PositiveNumber`)
2. Enforce invariants at the type level
3. Make illegal states unrepresentable
4. Create self-documenting APIs through type signatures

### Goals

1. **Type Safety**: Enable users to encode business rules in types
2. **Explicitness**: All validation must be visible and mandatory
3. **Reproducibility**: Type definitions are declarative and deterministic
4. **LLM Collaboration**: Clear, parseable syntax for AI assistance
5. **No Implicit Behavior**: Users explicitly handle all error cases

### Non-Goals

- Structural typing (incompatible with safety goals)
- Optional validators (defeats the safety guarantee)
- Implicit construction (bypasses validation)
- Type classes or traits (future consideration)
- Dependent types (out of scope)

---

## Design Principles

### 1. Explicit Over Implicit

Every aspect of type definition and usage must be visible:
- Validator parameters are explicit
- Return types are explicit (must be `Result<T, E>`)
- Error handling is mandatory
- Field access requires pattern matching on `Result`

### 2. Safety Through Impossibility

Rather than warn users about unsafe practices, make them impossible:
- No direct object construction syntax
- Validators are not optional—they're part of the type definition
- The only way to create a value is through the validator

### 3. Fail Fast, Fail Explicitly

- Validation happens at construction time
- Errors are values, not exceptions
- Users must explicitly handle both success and failure cases
- No silent failures or NA propagation

### 4. Align with T's Philosophy

- Reproducibility: Type definitions are pure and deterministic
- No mutable state: Types are immutable after creation
- Pipeline-friendly: Types work naturally in pipelines
- LLM-parseable: Clear, unambiguous syntax

---

## Language Syntax

### Basic Product Types

Product types are records with named fields:

```t
type TypeName = {
  field1: Type1,
  field2: Type2,
  ...
} validate (field1, field2, ...) -> Result<TypeName, ErrorType> {
  -- Validation logic
  -- Must explicitly return Ok(...) or Error(...)
}
```

**Example: Date Type**

```t
type Date = {
  year: int,
  month: int,
  day: int
} validate (year, month, day) -> Result<Date, string> {
  if (month < 1 || month > 12) {
    return Error("Month must be between 1-12, got: " ++ int_to_string(month))
  }
  
  if (day < 1 || day > 31) {
    return Error("Day must be between 1-31, got: " ++ int_to_string(day))
  }
  
  days_in_month = get_days_in_month(year, month)
  if (day > days_in_month) {
    return Error("Day " ++ int_to_string(day) ++ " doesn't exist in month " ++ int_to_string(month))
  }
  
  -- Explicit success: construct and return
  return Ok({ year: year, month: month, day: day })
}
```

### Sum Types (Tagged Unions)

Sum types represent alternatives with distinct variants:

```t
type TypeName =
  | VariantName1 {
      field1: Type1,
      ...
    } validate (field1, ...) -> Result<TypeName, ErrorType> {
      -- Validation for this variant
    }
    
  | VariantName2 {
      field1: Type1,
      ...
    } validate (field1, ...) -> Result<TypeName, ErrorType> {
      -- Validation for this variant
    }
```

**Example: Payment Type**

```t
type Payment =
  | CreditCard {
      card_number: string,
      cvv: string,
      expiry: string
    } validate (card_number, cvv, expiry) -> Result<Payment, string> {
      if (string_length(card_number) != 16) {
        return Error("Card number must be 16 digits")
      }
      if (string_length(cvv) != 3) {
        return Error("CVV must be 3 digits")
      }
      -- Explicit tag construction
      return Ok({ tag: "CreditCard", card_number, cvv, expiry })
    }
    
  | BankTransfer {
      account_number: string,
      routing_number: string
    } validate (account_number, routing_number) -> Result<Payment, string> {
      if (string_length(account_number) != 10) {
        return Error("Account number must be 10 digits")
      }
      return Ok({ tag: "BankTransfer", account_number, routing_number })
    }
    
  | Cash {
      amount: float
    } validate (amount) -> Result<Payment, string> {
      if (amount <= 0.0) {
        return Error("Cash amount must be positive")
      }
      return Ok({ tag: "Cash", amount })
    }
```

### Custom Error Types

Error types are themselves sum types, but validators are optional for error types:

```t
-- Error types can be defined without validators
type DateError =
  | InvalidMonth { month: int, min: int, max: int }
  | InvalidDay { day: int, month: int, max_days: int }
  | InvalidYear { year: int, reason: string }

-- Use in validators
type Date = {
  year: int,
  month: int,
  day: int
} validate (year, month, day) -> Result<Date, DateError> {
  if (month < 1 || month > 12) {
    return Error(DateError.InvalidMonth({ month, min: 1, max: 12 }))
  }
  
  days_in_month = get_days_in_month(year, month)
  if (day < 1 || day > days_in_month) {
    return Error(DateError.InvalidDay({ day, month, max_days: days_in_month }))
  }
  
  return Ok({ year, month, day })
}
```

---

## Type System Integration

### Type Hierarchy

```
Type ::=
  | PrimitiveType        -- int, float, string, bool
  | VectorType           -- Vector<T>
  | DataFrameType        -- DataFrame
  | FunctionType         -- T1 -> T2
  | ResultType           -- Result<T, E>
  | CustomType           -- User-defined types
    | ProductType        -- Record types
    | SumType            -- Tagged unions
```

### Result Type

The `Result<T, E>` type is a built-in sum type:

```t
-- Built-in definition (not user-visible, but conceptually)
type Result<T, E> =
  | Ok { value: T }
  | Error { error: E }
```

All custom type constructors return `Result<T, E>` where:
- `T` is the custom type being constructed
- `E` is the error type (string or custom error type)

### Type Construction

Custom types are constructed using a constructor function automatically generated from the type definition:

```t
-- For product types:
TypeName(arg1, arg2, ...) -> Result<TypeName, ErrorType>

-- For sum types:
TypeName.VariantName(arg1, arg2, ...) -> Result<TypeName, ErrorType>
```

**Prohibited Constructions:**

```t
-- ❌ Direct object literal (compile error)
let bad = { year: 2026, month: 2, day: 12 }

-- ❌ Direct tag construction (compile error)
let bad = { tag: "Date", year: 2026, month: 2, day: 12 }

-- ✅ Only through constructor
let result = Date(2026, 2, 12)  -- Returns Result<Date, string>
```

---

## Semantic Rules

### Rule 1: Mandatory Validator Block

**Requirement**: Every custom type definition MUST include a `validate` block.

**Enforcement**: Compile-time error if `validate` block is missing.

```t
-- ❌ Compile error: Missing validator
type BadType = {
  value: int
}

-- ✅ Valid: Validator present
type GoodType = {
  value: int
} validate (value) -> Result<GoodType, string> {
  if (value < 0) {
    return Error("Value must be non-negative")
  }
  return Ok({ value })
}
```

### Rule 2: Explicit Return Type

**Requirement**: Validator must explicitly declare return type as `Result<TypeName, ErrorType>`.

**Enforcement**: Type checker verifies return type matches declaration.

```t
-- ❌ Type error: Return type mismatch
type BadType = {
  value: int
} validate (value) -> int {  -- Wrong return type
  return value
}

-- ✅ Valid: Correct return type
type GoodType = {
  value: int
} validate (value) -> Result<GoodType, string> {
  return Ok({ value })
}
```

### Rule 3: Exhaustive Return

**Requirement**: All code paths in validator must return `Ok(...)` or `Error(...)`.

**Enforcement**: Compiler checks for exhaustive returns (similar to match expressions).

```t
-- ❌ Compile error: Missing return in some path
type BadType = {
  value: int
} validate (value) -> Result<BadType, string> {
  if (value < 0) {
    return Error("Negative")
  }
  -- Missing return here!
}

-- ✅ Valid: All paths return
type GoodType = {
  value: int
} validate (value) -> Result<GoodType, string> {
  if (value < 0) {
    return Error("Negative")
  }
  return Ok({ value })  -- Explicit success path
}
```

### Rule 4: Validator Purity

**Requirement**: Validators must be pure functions (no side effects, no I/O).

**Enforcement**: Static analysis detects impure operations in validator blocks.

```t
-- ❌ Compile error: Side effects in validator
type BadType = {
  value: int
} validate (value) -> Result<BadType, string> {
  print("Validating...")  -- Side effect!
  return Ok({ value })
}

-- ✅ Valid: Pure validation
type GoodType = {
  value: int
} validate (value) -> Result<GoodType, string> {
  is_valid = value >= 0  -- Pure computation
  if (is_valid) {
    return Ok({ value })
  } else {
    return Error("Invalid")
  }
}
```

### Rule 5: Constructor Uniqueness

**Requirement**: Type names and variant names must be unique within their scope.

**Enforcement**: Compile-time error on duplicate names.

```t
-- ❌ Compile error: Duplicate type name
type Date = { day: int } validate (day) -> Result<Date, string> { ... }
type Date = { year: int } validate (year) -> Result<Date, string> { ... }

-- ❌ Compile error: Duplicate variant name
type Payment =
  | Card { number: string } validate (...) { ... }
  | Card { type: string } validate (...) { ... }  -- Duplicate!
```

### Rule 6: No Recursive Validators

**Requirement**: Validators cannot directly or indirectly call themselves.

**Enforcement**: Cycle detection in validator call graph.

```t
-- ❌ Compile error: Recursive validator
type Node = {
  value: int,
  next: Node  -- This would require recursive validation
} validate (value, next) -> Result<Node, string> {
  -- Cannot validate 'next' because it requires Node.validate
  ...
}
```

**Note**: Recursive data structures require a different approach (future work).

---

## Runtime Behavior

### Constructor Function Generation

For each type definition, the compiler generates a constructor function:

```t
-- User writes:
type Date = {
  year: int,
  month: int,
  day: int
} validate (year, month, day) -> Result<Date, string> {
  -- validation code
}

-- Compiler generates (conceptually):
Date: (int, int, int) -> Result<Date, string>
Date = \(year, month, day) -> 
  -- Run validation logic from validate block
  -- Return Result<Date, string>
```

### Validation Execution

Validation happens immediately when the constructor is called:

```t
-- User code:
result = Date(2026, 2, 12)

-- Runtime behavior:
-- 1. Extract arguments: year=2026, month=2, day=12
-- 2. Execute validator code with these arguments
-- 3. Return Result<Date, string> based on validation outcome
```

### Field Access

Fields can only be accessed after pattern matching on the `Result`:

```t
result = Date(2026, 2, 12)

-- ❌ Compile error: Cannot access field on Result type
print(result.year)

-- ✅ Valid: Pattern match first
match result {
  Ok(date) => print(date.year)  -- date has type Date
  Error(msg) => print(msg)      -- msg has type string
}
```

### Sum Type Tags

For sum types, the compiler automatically adds a `tag` field:

```t
type Payment =
  | CreditCard { card_number: string } validate (...) { 
      return Ok({ tag: "CreditCard", card_number })
    }
  | Cash { amount: float } validate (...) { 
      return Ok({ tag: "Cash", amount })
    }

-- Runtime representation:
-- CreditCard variant: { tag: "CreditCard", card_number: "1234..." }
-- Cash variant: { tag: "Cash", amount: 100.0 }
```

### Pipeline Integration

Custom types work naturally in T's pipeline operators:

```t
-- Using |> pipe
result = Date(2026, 2, 12) |> match {
  Ok(date) => format_date(date)
  Error(msg) => "Invalid: " ++ msg
}

-- Using ?|> maybe-pipe for error recovery
date = Date(2026, 13, 5) ?|> \(res) -> match res {
  Ok(d) => d
  Error(_) => Date(2026, 1, 1) |> unwrap  -- Fallback date
}
```

---

## Error Handling

### Simple String Errors

For straightforward validation, use string error messages:

```t
type PositiveNumber = {
  value: float
} validate (value) -> Result<PositiveNumber, string> {
  if (value <= 0.0) {
    return Error("Value must be positive, got: " ++ float_to_string(value))
  }
  return Ok({ value })
}

-- Usage:
match PositiveNumber(-5.0) {
  Ok(num) => print("Valid: " ++ float_to_string(num.value))
  Error(msg) => print("Error: " ++ msg)
}
```

### Structured Error Types

For complex validation, define custom error types:

```t
-- Define error type (validators optional for error types)
type ValidationError =
  | OutOfRange { value: float, min: float, max: float }
  | InvalidFormat { input: string, expected: string }
  | MissingField { field: string }

-- Use in validator
type Age = {
  value: int
} validate (value) -> Result<Age, ValidationError> {
  if (value < 0 || value > 150) {
    return Error(ValidationError.OutOfRange({ 
      value: int_to_float(value), 
      min: 0.0, 
      max: 150.0 
    }))
  }
  return Ok({ value })
}

-- Exhaustive error handling
match Age(200) {
  Ok(age) => print("Valid age: " ++ int_to_string(age.value))
  Error(err) => match err {
    OutOfRange { value, min, max } => 
      print("Age " ++ float_to_string(value) ++ " out of range [" ++ 
            float_to_string(min) ++ ", " ++ float_to_string(max) ++ "]")
    InvalidFormat { input, expected } => 
      print("Format error")
    MissingField { field } => 
      print("Missing: " ++ field)
  }
}
```

### Error Composition

Validators can call other validators and compose errors:

```t
type Day = {
  value: int
} validate (value) -> Result<Day, string> {
  if (value < 1 || value > 31) {
    return Error("Day out of range")
  }
  return Ok({ value })
}

type Month = {
  value: int
} validate (value) -> Result<Month, string> {
  if (value < 1 || value > 12) {
    return Error("Month out of range")
  }
  return Ok({ value })
}

type Date = {
  year: int,
  month: Month,
  day: Day
} validate (year, month_val, day_val) -> Result<Date, string> {
  -- Validate month
  month_result = Month(month_val)
  month = match month_result {
    Ok(m) => m
    Error(msg) => return Error(msg)  -- Propagate error
  }
  
  -- Validate day
  day_result = Day(day_val)
  day = match day_result {
    Ok(d) => d
    Error(msg) => return Error(msg)  -- Propagate error
  }
  
  return Ok({ year, month, day })
}
```

---

## Pattern Matching

### Product Type Matching

```t
type Point = {
  x: float,
  y: float
} validate (x, y) -> Result<Point, string> {
  return Ok({ x, y })
}

result = Point(3.0, 4.0)

match result {
  Ok(point) => {
    -- Destructure fields
    match point {
      { x, y } => print("Point at (" ++ float_to_string(x) ++ 
                        ", " ++ float_to_string(y) ++ ")")
    }
  }
  Error(msg) => print("Error: " ++ msg)
}

-- Nested pattern matching (shorthand)
match Point(3.0, 4.0) {
  Ok({ x, y }) => print("x=" ++ float_to_string(x))
  Error(msg) => print(msg)
}
```

### Sum Type Matching

```t
type Shape =
  | Circle { radius: float } validate (radius) -> Result<Shape, string> {
      if (radius <= 0.0) { return Error("Radius must be positive") }
      return Ok({ tag: "Circle", radius })
    }
  | Rectangle { width: float, height: float } validate (width, height) -> Result<Shape, string> {
      if (width <= 0.0 || height <= 0.0) { return Error("Dimensions must be positive") }
      return Ok({ tag: "Rectangle", width, height })
    }

calculate_area = \(shape_result) -> match shape_result {
  Ok(shape) => match shape {
    { tag: "Circle", radius } => 3.14159 * radius * radius
    { tag: "Rectangle", width, height } => width * height
  }
  Error(msg) => 0.0  -- Or handle error appropriately
}

area1 = calculate_area(Shape.Circle(5.0))
area2 = calculate_area(Shape.Rectangle(4.0, 6.0))
```

### Exhaustiveness Checking

The compiler ensures all patterns are matched:

```t
-- ❌ Compile error: Non-exhaustive match
match Shape.Circle(5.0) {
  Ok(shape) => match shape {
    { tag: "Circle", radius } => print("Circle")
    -- Missing Rectangle case!
  }
  Error(msg) => print(msg)
}

-- ✅ Valid: All variants covered
match Shape.Circle(5.0) {
  Ok(shape) => match shape {
    { tag: "Circle", radius } => print("Circle")
    { tag: "Rectangle", width, height } => print("Rectangle")
  }
  Error(msg) => print(msg)
}
```

---

## Examples

### Example 1: Email Address Type

```t
type Email = {
  address: string
} validate (address) -> Result<Email, string> {
  -- Simple validation: must contain @ and .
  has_at = string_contains(address, "@")
  has_dot = string_contains(address, ".")
  
  if (!has_at) {
    return Error("Email must contain @")
  }
  
  if (!has_dot) {
    return Error("Email must contain .")
  }
  
  parts = string_split(address, "@")
  if (length(parts) != 2) {
    return Error("Email must have exactly one @")
  }
  
  return Ok({ address })
}

-- Usage in data pipeline
contacts = read_csv("contacts.csv")

validated_contacts = contacts
  |> mutate($email_result = Email($email_str))
  |> filter(match $email_result { Ok(_) => true, Error(_) => false })
  |> mutate($email = match $email_result { Ok(e) => e.address, Error(_) => "" })
  |> select($name, $email)
```

### Example 2: Temperature Type with Units

```t
type TemperatureUnit =
  | Celsius
  | Fahrenheit
  | Kelvin

type Temperature =
  | Celsius { value: float } validate (value) -> Result<Temperature, string> {
      if (value < -273.15) {
        return Error("Temperature below absolute zero")
      }
      return Ok({ tag: "Celsius", value })
    }
  | Fahrenheit { value: float } validate (value) -> Result<Temperature, string> {
      if (value < -459.67) {
        return Error("Temperature below absolute zero")
      }
      return Ok({ tag: "Fahrenheit", value })
    }
  | Kelvin { value: float } validate (value) -> Result<Temperature, string> {
      if (value < 0.0) {
        return Error("Temperature below absolute zero")
      }
      return Ok({ tag: "Kelvin", value })
    }

-- Conversion function
to_celsius = \(temp_result) -> match temp_result {
  Ok(temp) => match temp {
    { tag: "Celsius", value } => value
    { tag: "Fahrenheit", value } => (value - 32.0) * 5.0 / 9.0
    { tag: "Kelvin", value } => value - 273.15
  }
  Error(msg) => NA  -- Or handle error appropriately
}

-- Usage
temp1 = Temperature.Celsius(25.0)
temp2 = Temperature.Fahrenheit(77.0)

print(to_celsius(temp1))  -- 25.0
print(to_celsius(temp2))  -- 25.0
```

### Example 3: Non-Empty List Type

```t
type NonEmptyList<T> = {
  head: T,
  tail: Vector<T>
} validate (head, tail) -> Result<NonEmptyList<T>, string> {
  -- Validation is trivial: having a head guarantees non-empty
  return Ok({ head, tail })
}

-- Helper constructor from vector
from_vector = \(vec) -> {
  if (length(vec) == 0) {
    return Error("Cannot create NonEmptyList from empty vector")
  }
  
  head = vec[0]
  tail = slice(vec, 1, length(vec))
  
  return NonEmptyList(head, tail)
}

-- Usage
result = from_vector([1, 2, 3, 4, 5])

match result {
  Ok(nel) => {
    print("First: " ++ int_to_string(nel.head))
    print("Rest: " ++ vector_to_string(nel.tail))
  }
  Error(msg) => print("Error: " ++ msg)
}
```

### Example 4: Bounded Integer Type

```t
type BoundedInt = {
  value: int,
  min: int,
  max: int
} validate (value, min, max) -> Result<BoundedInt, string> {
  if (min > max) {
    return Error("Invalid bounds: min > max")
  }
  
  if (value < min) {
    return Error("Value " ++ int_to_string(value) ++ 
                 " below minimum " ++ int_to_string(min))
  }
  
  if (value > max) {
    return Error("Value " ++ int_to_string(value) ++ 
                 " above maximum " ++ int_to_string(max))
  }
  
  return Ok({ value, min, max })
}

-- Type aliases for common ranges (future feature)
type Percentage = BoundedInt with (value, 0, 100)
type DayOfMonth = BoundedInt with (value, 1, 31)
```

### Example 5: Result Chaining in Pipelines

```t
type UserId = {
  id: int
} validate (id) -> Result<UserId, string> {
  if (id <= 0) {
    return Error("User ID must be positive")
  }
  return Ok({ id })
}

type User = {
  user_id: UserId,
  name: string,
  age: int
} validate (user_id_val, name, age) -> Result<User, string> {
  -- Validate user_id first
  user_id_result = UserId(user_id_val)
  user_id = match user_id_result {
    Ok(uid) => uid
    Error(msg) => return Error("Invalid user_id: " ++ msg)
  }
  
  -- Validate age
  if (age < 0 || age > 150) {
    return Error("Invalid age: " ++ int_to_string(age))
  }
  
  -- Validate name
  if (string_length(name) == 0) {
    return Error("Name cannot be empty")
  }
  
  return Ok({ user_id, name, age })
}

-- Pipeline with validation
users_df = read_csv("users.csv")

validated_users = users_df
  |> mutate($user_result = User($id, $name, $age))
  |> mutate($is_valid = match $user_result {
       Ok(_) => true
       Error(_) => false
     })
  |> mutate($error_msg = match $user_result {
       Ok(_) => ""
       Error(msg) => msg
     })

-- Split into valid and invalid
valid_users = validated_users 
  |> filter($is_valid)
  |> mutate($user = match $user_result { Ok(u) => u, Error(_) => NA })

invalid_users = validated_users 
  |> filter(!$is_valid)
  |> select($id, $name, $age, $error_msg)
```

---

## Implementation Phases

### Phase 1: Core Type System (Sprint 1-2)

**Goal**: Implement basic product types with validation

**Tasks**:
1. Extend AST to represent type definitions
   - `TypeDef` node with fields and validator
   - `ValidatorBlock` node with parameters and body
   - Constructor expression node
2. Extend lexer/parser
   - Keywords: `type`, `validate`, `return`
   - Parse type definitions with validator blocks
   - Parse constructor calls
3. Implement type checker
   - Verify validator return type is `Result<T, E>`
   - Check exhaustive returns in validator
   - Ensure validator purity (no side effects)
4. Implement evaluator
   - Generate constructor functions
   - Execute validators at construction time
   - Return `Result<T, E>` values
5. Implement pattern matching for custom types
   - Extend match expressions to handle custom types
   - Field destructuring in patterns

**Deliverables**:
- Basic product types working
- Simple validation logic
- Pattern matching support
- Unit tests for core functionality

### Phase 2: Sum Types (Sprint 3-4)

**Goal**: Add support for tagged unions

**Tasks**:
1. Extend AST for sum type definitions
   - Multiple variants with individual validators
   - Automatic tag field generation
2. Update type checker
   - Per-variant validation
   - Unique variant names within type
3. Implement variant constructors
   - `TypeName.VariantName(...)` syntax
   - Tag injection at construction time
4. Extend pattern matching
   - Tag-based matching for sum types
   - Exhaustiveness checking for all variants

**Deliverables**:
- Sum types with multiple variants
- Per-variant validation
- Exhaustive pattern matching
- Integration tests

### Phase 3: Error Types & Composition (Sprint 5)

**Goal**: Custom error types and error composition

**Tasks**:
1. Allow sum types without validators (for error types)
2. Implement error propagation patterns
3. Add helper functions for Result manipulation
   - `map`, `and_then`, `or_else` for Result types
4. Document error handling best practices

**Deliverables**:
- Custom error type definitions
- Error composition examples
- API documentation

### Phase 4: Integration & Optimization (Sprint 6-7)

**Goal**: Integrate with existing T features and optimize

**Tasks**:
1. DataFrame integration
   - Use custom types in mutate operations
   - Handle Result values in pipelines
2. Pipeline integration
   - Validate custom types work in pipeline blocks
   - Error handling in DAG execution
3. Performance optimization
   - Minimize validation overhead
   - Cache validated values where appropriate
4. Documentation
   - User guide for custom types
   - API reference
   - Migration guide for existing code

**Deliverables**:
- Full integration with T's features
- Performance benchmarks
- Complete documentation

### Phase 5: Advanced Features (Future)

**Stretch goals** (post-Beta):
1. Generic types: `type Option<T> = ...`
2. Recursive types: `type Tree = Leaf | Node { left: Tree, right: Tree }`
3. Type aliases: `type UserId = BoundedInt with (...)`
4. Phantom types for zero-cost abstraction
5. Refinement types: more expressive invariants

---

## Testing Strategy

### Unit Tests

Test individual components in isolation:

```ocaml
(* Parser tests *)
let%test "parse_product_type" = ...
let%test "parse_sum_type" = ...
let%test "parse_validator_block" = ...

(* Type checker tests *)
let%test "reject_missing_validator" = ...
let%test "reject_non_result_return_type" = ...
let%test "reject_impure_validator" = ...

(* Evaluator tests *)
let%test "construct_valid_value" = ...
let%test "reject_invalid_value" = ...
let%test "pattern_match_custom_type" = ...
```

### Integration Tests

Test complete workflows:

```t
-- Test file: tests/custom_types/date_validation.t

type Date = {
  year: int,
  month: int,
  day: int
} validate (year, month, day) -> Result<Date, string> {
  if (month < 1 || month > 12) {
    return Error("Invalid month")
  }
  return Ok({ year, month, day })
}

-- Test valid date
assert_ok(Date(2026, 2, 12))

-- Test invalid date
assert_error(Date(2026, 13, 5))

-- Test pattern matching
match Date(2026, 2, 12) {
  Ok(date) => assert_equal(date.month, 2)
  Error(_) => assert_fail("Expected Ok")
}
```

### Property-Based Tests

Use QuickCheck-style property testing:

```ocaml
(* Property: Valid inputs always succeed *)
let%test "valid_dates_always_succeed" =
  QCheck.Test.make 
    ~count:1000
    (QCheck.triple 
      (QCheck.int_range 1900 2100)
      (QCheck.int_range 1 12)
      (QCheck.int_range 1 31))
    (fun (year, month, day) ->
      match validate_date year month day with
      | Ok _ -> true
      | Error _ -> (* Check if actually invalid *) ...)

(* Property: Invalid inputs always fail *)
let%test "invalid_months_always_fail" =
  QCheck.Test.make
    ~count:1000
    (QCheck.int_range 13 100)
    (fun invalid_month ->
      match validate_date 2026 invalid_month 15 with
      | Error _ -> true
      | Ok _ -> false)
```

### Regression Tests

Capture and prevent bugs:

```t
-- Issue #123: Validator allowed negative years
type Date = { year: int, month: int, day: int }
  validate (year, month, day) -> Result<Date, string> {
    if (year < 0) {
      return Error("Year cannot be negative")
    }
    -- ... other validation
  }

assert_error(Date(-1, 1, 1))  -- Should fail
```

### Performance Tests

Benchmark validation overhead:

```ocaml
let%bench "validate_date_success" =
  Date.validate 2026 2 12

let%bench "validate_date_failure" =
  Date.validate 2026 13 5

let%bench "construct_1000_dates" =
  List.init 1000 (fun i -> Date.validate 2026 1 (i mod 28 + 1))
```

---

## Open Questions

### 1. Generic Types

**Question**: Should Phase 1 include generic types like `Option<T>` or `Result<T, E>`?

**Options**:
- A) Include in Phase 1 (more work, but more powerful)
- B) Defer to Phase 5 (simpler initial implementation)
- C) Only built-in generics like Result (compromise)

**Recommendation**: Option C - keep Result as built-in generic, defer user-defined generics

### 2. Recursive Types

**Question**: How should we handle recursive types like linked lists or trees?

**Challenge**: Validators for recursive types need to validate recursively, which conflicts with Rule 6 (no recursive validators).

**Possible Solutions**:
- Lazy validation: Only validate top level, defer nested validation
- Structural recursion: Allow recursion with termination checking
- External validation: Separate validator from type definition

**Recommendation**: Defer to Phase 5, needs more design work

### 3. Type Inference

**Question**: Should constructor calls require explicit type annotations?

```t
-- Option A: Inferred (more convenient)
result = Date(2026, 2, 12)  -- Inferred: Result<Date, string>

-- Option B: Explicit (more clear)
result: Result<Date, string> = Date(2026, 2, 12)
```

**Recommendation**: Allow inference but permit explicit annotations

### 4. Validator Composition

**Question**: Should we provide built-in combinators for validator composition?

```t
-- Hypothetical syntax:
type Date = {
  year: int,
  month: Month,  -- Month is another custom type
  day: Day       -- Day is another custom type
} validate_compose  -- Automatically compose Month and Day validators
```

**Recommendation**: Start explicit (Phase 1-3), add helpers in Phase 4 if needed

### 5. Constructor Naming

**Question**: Should sum type constructors require the type prefix?

```t
-- Option A: Prefixed (explicit, no ambiguity)
Payment.CreditCard("1234...", "123", "12/26")

-- Option B: Unprefixed (concise, potential ambiguity)
CreditCard("1234...", "123", "12/26")
```

**Recommendation**: Option A - explicit and unambiguous

### 6. Error Recovery in Pipelines

**Question**: How should pipelines handle Result types from custom type constructors?

```t
-- Current approach: Manual matching
df |> mutate($date_result = Date($year, $month, $day))
   |> filter(match $date_result { Ok(_) => true, Error(_) => false })

-- Alternative: Built-in Result handling
df |> mutate_validated($date = Date($year, $month, $day))  -- Filters errors automatically
```

**Recommendation**: Start with manual matching (explicit), consider helpers in Phase 4

---

## Appendix: Grammar Changes

### Extended BNF

```bnf
(* Type definitions *)
type_def ::=
  | "type" TYPE_NAME "=" product_type validate_block
  | "type" TYPE_NAME "=" sum_type

product_type ::=
  "{" field_list "}"

field_list ::=
  | field
  | field "," field_list

field ::=
  IDENT ":" type_expr

sum_type ::=
  "|" variant
  | "|" variant sum_type

variant ::=
  VARIANT_NAME "{" field_list "}" validate_block

validate_block ::=
  "validate" "(" param_list ")" "->" result_type "{" stmt_list "}"

result_type ::=
  "Result" "<" type_expr "," type_expr ">"

(* Constructor calls *)
expr ::=
  | ...
  | TYPE_NAME "(" expr_list ")"                    (* Product type constructor *)
  | TYPE_NAME "." VARIANT_NAME "(" expr_list ")"   (* Sum type constructor *)
```

---

## Appendix: Implementation Notes

### AST Extensions

```ocaml
(* ast.ml additions *)

type type_def =
  | ProductType of {
      name: string;
      fields: (string * type_expr) list;
      validator: validator_block;
    }
  | SumType of {
      name: string;
      variants: variant list;
    }

and variant = {
  name: string;
  fields: (string * type_expr) list;
  validator: validator_block;
}

and validator_block = {
  params: string list;
  return_type: type_expr;
  body: stmt list;
}

and type_expr =
  | TInt
  | TFloat
  | TString
  | TBool
  | TVector of type_expr
  | TDataFrame
  | TFunction of type_expr * type_expr
  | TResult of type_expr * type_expr
  | TCustom of string
```

### Type Checker Extensions

```ocaml
(* typecheck.ml additions *)

(* Environment tracks custom type definitions *)
type type_env = {
  types: (string, type_def) Hashtbl.t;
  constructors: (string, type_expr) Hashtbl.t;
}

(* Check type definition *)
let check_type_def env type_def =
  match type_def with
  | ProductType { name; fields; validator } ->
      (* Check validator returns Result<name, _> *)
      check_validator_return_type validator name;
      (* Check validator is pure *)
      check_validator_purity validator.body;
      (* Check exhaustive returns *)
      check_exhaustive_return validator.body;
      (* Register constructor *)
      register_constructor env name fields

  | SumType { name; variants } ->
      List.iter (fun variant ->
        check_variant env name variant
      ) variants

(* Check constructor call *)
let check_constructor_call env name args =
  match Hashtbl.find_opt env.constructors name with
  | Some fn_type ->
      (* Check argument types match *)
      check_function_application fn_type args
  | None ->
      type_error ("Unknown constructor: " ^ name)
```

### Evaluator Extensions

```ocaml
(* eval.ml additions *)

(* Evaluate type definition - generates constructor *)
let eval_type_def env type_def =
  match type_def with
  | ProductType { name; fields; validator } ->
      let constructor = make_constructor fields validator in
      Env.bind env name (VConstructor constructor)
      
  | SumType { name; variants } ->
      List.iter (fun variant ->
        let constructor = make_variant_constructor name variant in
        let full_name = name ^ "." ^ variant.name in
        Env.bind env full_name (VConstructor constructor)
      ) variants

(* Make constructor function *)
let make_constructor fields validator =
  fun args ->
    (* Extract field values from args *)
    let field_vals = bind_fields fields args in
    (* Execute validator *)
    let result = eval_validator validator field_vals in
    (* Return Result<T, E> *)
    result

(* Execute validator block *)
let eval_validator validator field_vals =
  let env = Env.extend Env.empty field_vals in
  eval_stmt_list env validator.body
```

# Implementation Extension: Multiple Dispatch for Custom Types

## Overview

This document extends the Custom Types implementation with **multiple dispatch** support, allowing users to define generic functions that dispatch to different implementations based on argument types. This enables polymorphic behavior while maintaining T's principles of explicitness and type safety.

---

## Motivation

### Problem

With custom types, users need to define operations that work on different types:

```t
-- How do we make head() work for different types?
head(some_dataframe)  -- Should return first few rows
head(some_vector)     -- Should return first few elements  
head(some_dog)        -- Should return... the dog's head? Custom behavior!
```

Without dispatch, users would need different function names for each type:
```t
head_dataframe(df)
head_vector(vec)
head_dog(dog)
```

This is verbose, non-idiomatic, and doesn't match R's tidyverse UX.

### Goals

1. **Polymorphic functions**: One function name, multiple implementations
2. **Type-safe dispatch**: Compiler verifies method signatures match generic
3. **Explicit registration**: Clear, visible method definitions
4. **Multiple dispatch**: Support dispatch on multiple arguments (not just first)
5. **Exhaustiveness checking**: Warn if not all types have methods
6. **No ambiguity**: Clear resolution order for overlapping methods

---

## Design Overview

### Core Concepts

1. **Generic Function**: A function signature that can be implemented for multiple types
2. **Method**: A concrete implementation of a generic for specific types
3. **Dispatch**: Runtime selection of the correct method based on argument types
4. **Method Table**: Runtime lookup structure mapping types to implementations

### Three-Part Syntax

```t
-- 1. Declare generic function with signature
generic function_name: (Type1, Type2, ...) -> ReturnType

-- 2. Register methods for specific types
method(function_name, ConcreteType1, ConcreteType2, ...) = \(arg1, arg2, ...) -> {
  -- implementation
}

-- 3. Call function - dispatch happens automatically
result = function_name(value1, value2, ...)
```

---

## Syntax Specification

### Generic Function Declaration

```t
generic <function_name>: <type_signature>
```

**Components**:
- `generic`: Keyword indicating this is a dispatchable function
- `<function_name>`: Name of the generic function
- `<type_signature>`: Function type showing parameter and return types

**Examples**:

```t
-- Single argument dispatch
generic head: <T>(T) -> T

-- Multiple argument dispatch  
generic combine: <T, U>(T, U) -> T

-- Returning different type
generic to_string: <T>(T) -> string

-- Multiple parameters of same type
generic distance: <T>(T, T) -> float
```

### Method Registration

```t
method(<function_name>, <Type1>, <Type2>, ...) = <implementation>
```

**Components**:
- `method`: Keyword for registering a method
- `<function_name>`: Name of the generic function
- `<Type1>, <Type2>, ...`: Concrete types this method handles
- `<implementation>`: Lambda or function body

**Examples**:

```t
type Dog = {
  name: string,
  breed: string
} validate (name, breed) -> Result<Dog, string> {
  return Ok({ name, breed })
}

-- Register method for Dog type
generic head: <T>(T) -> string

method(head, Dog) = \(dog) -> {
  return "Dog head: " ++ dog.name
}

-- Register method for DataFrame
method(head, DataFrame) = \(df) -> {
  return df |> slice(0, 5)
}

-- Register method for Vector
method(head, Vector<T>) = \(vec) -> {
  return vec |> slice(0, 5)
}
```

### Multiple Dispatch

```t
-- Generic with multiple parameters
generic combine: <T, U>(T, U) -> T

-- Methods for different type combinations
method(combine, Dog, Dog) = \(dog1, dog2) -> {
  return Dog(dog1.name ++ " & " ++ dog2.name, dog1.breed)
}

method(combine, Dog, string) = \(dog, str) -> {
  return Dog(dog.name ++ str, dog.breed)
}

method(combine, DataFrame, DataFrame) = \(df1, df2) -> {
  return df1 |> bind_rows(df2)
}
```

---

## Semantic Rules

### Rule 1: Generic Declaration Required

**Requirement**: Methods can only be registered for declared generics.

```t
-- ❌ Compile error: head is not a generic
method(head, Dog) = \(dog) -> dog.name

-- ✅ Valid: generic declared first
generic head: <T>(T) -> string
method(head, Dog) = \(dog) -> dog.name
```

### Rule 2: Method Signature Must Match Generic

**Requirement**: Method implementation must match generic signature.

```t
generic head: <T>(T) -> string

-- ❌ Type error: Returns Dog, not string
method(head, Dog) = \(dog) -> dog

-- ❌ Type error: Takes two arguments, generic takes one
method(head, Dog) = \(dog, n) -> dog.name

-- ✅ Valid: Signature matches
method(head, Dog) = \(dog) -> dog.name
```

### Rule 3: No Duplicate Methods

**Requirement**: Cannot register multiple methods for the same type combination.

```t
generic head: <T>(T) -> string

method(head, Dog) = \(dog) -> dog.name

-- ❌ Compile error: Method already defined for Dog
method(head, Dog) = \(dog) -> dog.breed
```

### Rule 4: Method Must Handle Type's Structure

**Requirement**: Methods must correctly handle the custom type's structure.

```t
type Dog = {
  name: string,
  breed: string
} validate (name, breed) -> Result<Dog, string> { ... }

generic describe: <T>(T) -> string

-- Method receives validated Dog, not Result<Dog, E>
method(describe, Dog) = \(dog) -> {
  -- dog has type Dog here, not Result<Dog, string>
  return dog.name ++ " is a " ++ dog.breed
}

-- Usage:
match Dog("Buddy", "Labrador") {
  Ok(dog) => print(describe(dog))  -- Pass validated dog to generic
  Error(msg) => print("Error: " ++ msg)
}
```

### Rule 5: Exhaustiveness Warning

**Requirement**: Compiler warns if generic is called on types without methods.

```t
generic head: <T>(T) -> string

method(head, Dog) = \(dog) -> dog.name
method(head, DataFrame) = \(df) -> "DataFrame head"

-- ⚠️ Warning: No method defined for Vector<T>
result = head([1, 2, 3, 4, 5])  -- Runtime error if called
```

**Note**: This is a warning, not an error, because:
1. Generics can be extended later
2. Not all types may need methods
3. Users might intentionally handle only subset

### Rule 6: Dispatch Resolution Order

For multiple dispatch with type hierarchies (future feature), dispatch follows specificity:

1. **Exact match**: Most specific types first
2. **Generic match**: Generic type parameters second  
3. **Fallback**: Default implementation last (if provided)

```t
-- Most specific (both concrete types)
method(combine, Dog, Dog) = \(d1, d2) -> ...

-- Less specific (one generic)
method(combine, Dog, T) = \(dog, other) -> ...

-- Least specific (both generic) - acts as fallback
method(combine, T, U) = \(x, y) -> ...

-- Dispatch: combine(dog1, dog2) → uses method(Dog, Dog)
-- Dispatch: combine(dog, 42) → uses method(Dog, T)
-- Dispatch: combine(42, "hello") → uses method(T, U)
```

---

## Runtime Behavior

### Dispatch Mechanism

```t
-- User writes:
generic head: <T>(T) -> string
method(head, Dog) = \(dog) -> dog.name
method(head, DataFrame) = \(df) -> "DataFrame"

result = head(my_dog)

-- Runtime behavior:
-- 1. Evaluate my_dog to get value
-- 2. Inspect type of value
-- 3. Lookup method in dispatch table: head × Dog
-- 4. Call matched method with value
-- 5. Return result
```

### Method Table Structure

Internally, the runtime maintains a dispatch table:

```ocaml
(* Conceptual implementation *)
type method_table = {
  generic_name: string;
  methods: (type_pattern list * lambda) list;
}

(* Example table for 'head' generic *)
{
  generic_name: "head";
  methods: [
    ([Dog], \(dog) -> dog.name);
    ([DataFrame], \(df) -> "DataFrame");
    ([Vector<T>], \(vec) -> ...);
  ]
}
```

### Dispatch Algorithm

```ocaml
(* Simplified dispatch logic *)
let dispatch method_table types args =
  (* Find matching method *)
  match List.find_opt (fun (pattern, _) -> 
    types_match pattern types
  ) method_table.methods with
  | Some (_, lambda) -> 
      (* Apply method *)
      apply_lambda lambda args
  | None -> 
      (* No method found *)
      runtime_error ("No method defined for types: " ^ 
                     string_of_types types)
```

---

## Integration with Custom Types

### Working with Result Types

Since custom type constructors return `Result<T, E>`, methods receive validated values:

```t
type Dog = {
  name: string
} validate (name) -> Result<Dog, string> {
  if (string_length(name) == 0) {
    return Error("Name cannot be empty")
  }
  return Ok({ name })
}

generic greet: <T>(T) -> string

method(greet, Dog) = \(dog) -> {
  -- dog has type Dog (already validated)
  return "Hello, " ++ dog.name ++ "!"
}

-- Usage in pipeline:
match Dog("Buddy") {
  Ok(dog) => print(greet(dog))
  Error(msg) => print("Invalid dog: " ++ msg)
}

-- Or with error forwarding:
Dog("Buddy") 
  |> match {
       Ok(dog) => greet(dog)
       Error(msg) => "Error: " ++ msg
     }
  |> print
```

### Methods on Sum Types

```t
type Animal =
  | Dog { name: string } validate (name) -> Result<Animal, string> { ... }
  | Cat { name: string } validate (name) -> Result<Animal, string> { ... }

generic speak: <T>(T) -> string

-- Single method for all Animal variants
method(speak, Animal) = \(animal) -> {
  match animal {
    { tag: "Dog", name } => name ++ " says: Woof!"
    { tag: "Cat", name } => name ++ " says: Meow!"
  }
}

-- Or separate methods per variant (not recommended - use pattern matching instead)
-- Method receives full Animal type, then pattern matches internally
```

### Pipeline Integration

Generics work naturally in pipelines:

```t
type Dog = { name: string } validate (name) -> Result<Dog, string> { ... }

generic to_upper: <T>(T) -> T

method(to_upper, Dog) = \(dog) -> {
  match Dog(string_to_upper(dog.name)) {
    Ok(upper_dog) => upper_dog
    Error(_) => dog  -- Fallback to original
  }
}

-- Usage in pipeline:
match Dog("buddy") {
  Ok(dog) => 
    dog 
      |> to_upper 
      |> greet 
      |> print
  Error(msg) => print(msg)
}
```

---

## Examples

### Example 1: Basic Single Dispatch

```t
type Person = {
  name: string,
  age: int
} validate (name, age) -> Result<Person, string> {
  if (age < 0) {
    return Error("Age cannot be negative")
  }
  return Ok({ name, age })
}

type Company = {
  name: string,
  employees: int
} validate (name, employees) -> Result<Company, string> {
  return Ok({ name, employees })
}

-- Declare generic
generic describe: <T>(T) -> string

-- Register methods
method(describe, Person) = \(person) -> {
  return person.name ++ " is " ++ int_to_string(person.age) ++ " years old"
}

method(describe, Company) = \(company) -> {
  return company.name ++ " has " ++ int_to_string(company.employees) ++ " employees"
}

-- Usage
match Person("Alice", 30) {
  Ok(alice) => print(describe(alice))
  Error(msg) => print(msg)
}
-- Output: "Alice is 30 years old"

match Company("Acme Corp", 500) {
  Ok(acme) => print(describe(acme))
  Error(msg) => print(msg)
}
-- Output: "Acme Corp has 500 employees"
```

### Example 2: Multiple Dispatch

```t
type Dog = { name: string } validate (name) -> Result<Dog, string> { ... }
type Cat = { name: string } validate (name) -> Result<Cat, string> { ... }

-- Generic with two parameters
generic meet: <T, U>(T, U) -> string

-- Different implementations for different combinations
method(meet, Dog, Dog) = \(dog1, dog2) -> {
  return dog1.name ++ " and " ++ dog2.name ++ " sniff each other"
}

method(meet, Cat, Cat) = \(cat1, cat2) -> {
  return cat1.name ++ " and " ++ cat2.name ++ " ignore each other"
}

method(meet, Dog, Cat) = \(dog, cat) -> {
  return dog.name ++ " chases " ++ cat.name
}

method(meet, Cat, Dog) = \(cat, dog) -> {
  return cat.name ++ " hisses at " ++ dog.name
}

-- Usage
dog1 = Dog("Buddy") |> unwrap
dog2 = Dog("Max") |> unwrap
cat1 = Cat("Whiskers") |> unwrap

print(meet(dog1, dog2))
-- Output: "Buddy and Max sniff each other"

print(meet(dog1, cat1))
-- Output: "Buddy chases Whiskers"

print(meet(cat1, dog1))
-- Output: "Whiskers hisses at Buddy"
```

### Example 3: Generic with Numeric Operations

```t
type Money = {
  amount: float,
  currency: string
} validate (amount, currency) -> Result<Money, string> {
  if (amount < 0.0) {
    return Error("Amount cannot be negative")
  }
  return Ok({ amount, currency })
}

-- Declare generics for arithmetic
generic add: <T>(T, T) -> T
generic multiply: <T>(T, float) -> T

-- Implement for Money
method(add, Money, Money) = \(m1, m2) -> {
  if (m1.currency != m2.currency) {
    error("Cannot add different currencies")
  }
  match Money(m1.amount + m2.amount, m1.currency) {
    Ok(result) => result
    Error(msg) => error(msg)
  }
}

method(multiply, Money, float) = \(money, factor) -> {
  match Money(money.amount * factor, money.currency) {
    Ok(result) => result
    Error(msg) => error(msg)
  }
}

-- Usage
usd1 = Money(100.0, "USD") |> unwrap
usd2 = Money(50.0, "USD") |> unwrap

total = add(usd1, usd2)
print(total.amount)  -- 150.0

doubled = multiply(usd1, 2.0)
print(doubled.amount)  -- 200.0
```

### Example 4: DataFrame Methods

```t
type TimeSeries = {
  data: DataFrame,
  time_col: string,
  value_col: string
} validate (data, time_col, value_col) -> Result<TimeSeries, string> {
  -- Check columns exist
  cols = colnames(data)
  if (!contains(cols, time_col)) {
    return Error("Column " ++ time_col ++ " not found")
  }
  if (!contains(cols, value_col)) {
    return Error("Column " ++ value_col ++ " not found")
  }
  return Ok({ data, time_col, value_col })
}

-- Declare generics for data operations
generic head: <T>(T, int) -> T
generic filter: <T>(T, \(T) -> bool) -> T

-- Implement for TimeSeries
method(head, TimeSeries, int) = \(ts, n) -> {
  filtered_df = ts.data |> head(n)
  match TimeSeries(filtered_df, ts.time_col, ts.value_col) {
    Ok(result) => result
    Error(msg) => error(msg)
  }
}

method(filter, TimeSeries, \(TimeSeries) -> bool) = \(ts, predicate) -> {
  -- Filter based on predicate
  if (predicate(ts)) {
    return ts
  } else {
    empty_df = ts.data |> filter(\(row) -> false)
    match TimeSeries(empty_df, ts.time_col, ts.value_col) {
      Ok(result) => result
      Error(msg) => error(msg)
    }
  }
}

-- Usage
df = read_csv("timeseries.csv")
ts = TimeSeries(df, "timestamp", "value") |> unwrap

first_10 = head(ts, 10)
print(nrow(first_10.data))  -- 10
```

### Example 5: Chaining Generic Operations

```t
type Dog = { name: string, age: int } validate (...) -> Result<Dog, string> { ... }

generic to_upper: <T>(T) -> T
generic describe: <T>(T) -> string
generic age_years: <T>(T) -> int

method(to_upper, Dog) = \(dog) -> {
  match Dog(string_to_upper(dog.name), dog.age) {
    Ok(result) => result
    Error(_) => dog
  }
}

method(describe, Dog) = \(dog) -> {
  return dog.name ++ " is a dog"
}

method(age_years, Dog) = \(dog) -> {
  return dog.age
}

-- Usage: Chain generics in pipeline
match Dog("buddy", 5) {
  Ok(dog) => {
    result = dog 
      |> to_upper 
      |> describe 
      |> print
    -- Output: "BUDDY is a dog"
    
    years = dog |> age_years
    print(years)  -- 5
  }
  Error(msg) => print(msg)
}
```

---

## Standard Library Generics

T's standard library should provide common generics:

### Core Generics

```t
-- Conversion
generic to_string: <T>(T) -> string
generic to_int: <T>(T) -> int
generic to_float: <T>(T) -> float

-- Collection operations
generic length: <T>(T) -> int
generic head: <T>(T, int) -> T
generic tail: <T>(T, int) -> T
generic slice: <T>(T, int, int) -> T

-- Comparison
generic equal: <T>(T, T) -> bool
generic compare: <T>(T, T) -> int  -- -1, 0, 1

-- Display
generic print: <T>(T) -> unit
generic show: <T>(T) -> string
```

### Default Implementations

Built-in types have default method implementations:

```t
-- Automatically defined for Vector<T>
method(length, Vector<T>) = \(vec) -> vector_length(vec)
method(head, Vector<T>, int) = \(vec, n) -> vector_slice(vec, 0, n)
method(to_string, Vector<T>) = \(vec) -> vector_to_string(vec)

-- Automatically defined for DataFrame
method(length, DataFrame) = \(df) -> nrow(df)
method(head, DataFrame, int) = \(df, n) -> df |> slice(0, n)
method(to_string, DataFrame) = \(df) -> dataframe_to_string(df)

-- Automatically defined for primitives
method(to_string, int) = \(x) -> int_to_string(x)
method(to_string, float) = \(x) -> float_to_string(x)
method(to_string, bool) = \(x) -> if (x) "true" else "false"
```

---

## Implementation Plan

### Phase 1: Single Dispatch (Sprint 8-9)

**Goal**: Basic single-parameter dispatch

**Tasks**:
1. Extend AST for generic declarations and method registration
2. Implement generic function registry
3. Implement dispatch table and lookup
4. Type checker: Verify method signatures match generic
5. Evaluator: Runtime dispatch based on type tags
6. Error handling: No method found errors

**Deliverables**:
- Single-parameter generics working
- Method registration and dispatch
- Type checking for method signatures
- Unit tests

### Phase 2: Multiple Dispatch (Sprint 10)

**Goal**: Multi-parameter dispatch

**Tasks**:
1. Extend dispatch table for multiple parameters
2. Implement dispatch resolution for multiple types
3. Handle type specificity ordering
4. Update type checker for multi-param methods

**Deliverables**:
- Multiple parameter dispatch working
- Integration tests
- Documentation

### Phase 3: Standard Library Integration (Sprint 11)

**Goal**: Provide standard generics

**Tasks**:
1. Define core generics (to_string, length, head, etc.)
2. Implement default methods for built-in types
3. Documentation and examples
4. Migration guide for existing code

**Deliverables**:
- Complete standard library of generics
- Default implementations
- User guide

### Phase 4: Advanced Features (Future)

**Stretch goals**:
1. Generic constraints: `generic sum: <T: Numeric>(T, T) -> T`
2. Default methods: Fallback implementations
3. Method composition: Chain method lookups
4. Compile-time dispatch optimization

---

## Grammar Extensions

```bnf
(* Generic function declarations *)
generic_decl ::=
  "generic" IDENT ":" type_signature

(* Method registration *)
method_decl ::=
  "method" "(" IDENT "," type_list ")" "=" expr

type_list ::=
  | type_expr
  | type_expr "," type_list
```

---

## AST Extensions

```ocaml
(* ast.ml additions *)

type decl =
  | ... (* existing declarations *)
  | GenericDecl of generic_decl
  | MethodDecl of method_decl

and generic_decl = {
  name: string;
  type_sig: type_expr;
}

and method_decl = {
  generic_name: string;
  type_params: type_expr list;
  implementation: lambda;
}
```

---

## Type Checker Extensions

```ocaml
(* typecheck.ml additions *)

type generic_env = {
  generics: (string, type_expr) Hashtbl.t;
  methods: (string, method_entry list) Hashtbl.t;
}

and method_entry = {
  types: type_expr list;
  lambda_type: type_expr;
}

(* Check generic declaration *)
let check_generic_decl env generic_decl =
  (* Register generic in environment *)
  Hashtbl.add env.generics generic_decl.name generic_decl.type_sig

(* Check method registration *)
let check_method_decl env method_decl =
  (* Look up generic *)
  match Hashtbl.find_opt env.generics method_decl.generic_name with
  | None -> 
      type_error ("Generic not declared: " ^ method_decl.generic_name)
  | Some generic_type ->
      (* Check method signature matches generic *)
      let method_type = infer_lambda_type method_decl.implementation in
      check_signature_match generic_type method_type method_decl.type_params;
      (* Register method *)
      register_method env method_decl
```

---

## Testing Strategy

### Unit Tests

```ocaml
(* Test generic declaration *)
let%test "parse_generic_decl" = ...
let%test "reject_duplicate_generic" = ...

(* Test method registration *)
let%test "register_method" = ...
let%test "reject_method_without_generic" = ...
let%test "reject_signature_mismatch" = ...

(* Test dispatch *)
let%test "dispatch_single_param" = ...
let%test "dispatch_multi_param" = ...
let%test "error_no_method_found" = ...
```

### Integration Tests

```t
-- Test file: tests/dispatch/basic_dispatch.t

type Dog = { name: string } validate (name) -> Result<Dog, string> {
  return Ok({ name })
}

generic greet: <T>(T) -> string

method(greet, Dog) = \(dog) -> "Hello, " ++ dog.name

-- Test dispatch
dog = Dog("Buddy") |> unwrap
assert_equal(greet(dog), "Hello, Buddy")

-- Test missing method error
assert_error(greet(42))  -- No method for int
```

---

## Open Questions

### 1. Generic Type Parameters

Should generics support type parameters like `<T>` explicitly?

```t
-- Option A: Implicit (inferred from usage)
generic head: (T) -> T

-- Option B: Explicit type parameters
generic head<T>: (T) -> T
```

**Recommendation**: Start implicit (simpler), add explicit later if needed

### 2. Default Methods

Should generics allow fallback implementations?

```t
generic to_string: <T>(T) -> string default \(x) -> "unknown"

-- No method for Dog, uses default
print(to_string(my_dog))  -- "unknown"
```

**Recommendation**: No defaults initially (too implicit), reconsider in Phase 4

### 3. Method Visibility

Should methods be private/public?

```t
-- Option A: All methods public
method(greet, Dog) = ...

-- Option B: Private methods
private method(greet, Dog) = ...
```

**Recommendation**: All public initially, add visibility modifiers later if needed

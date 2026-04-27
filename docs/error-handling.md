# Error Handling in T

Comprehensive guide to error handling, recovery patterns, and debugging in T.

## Table of Contents

- [Error Philosophy](#error-philosophy)
- [Error Types](#error-types)
- [Error as Values](#error-as-values)
- [Pipe Operators and Errors](#pipe-operators-and-errors)
- [Pattern Matching and Errors](#pattern-matching-and-errors)
- [Error Recovery Patterns](#error-recovery-patterns)
- [Pipeline Diagnostics and Soft-Failures](#pipeline-diagnostics-and-soft-failures)
- [Polyglot Error Handling (Python/R)](#polyglot-error-handling-pythonr)
- [Common Errors](#common-errors)
- [Best Practices](#best-practices)

---

## Error Philosophy

T treats errors as **first-class values**, not exceptions. This design enables:

1. **Explicit Error Handling**: Errors don't crash programs; they flow through pipelines
2. **Railway-Oriented Programming**: Success and failure paths are explicit
3. **Composable Recovery**: Error handling logic can be pipelined like data
4. **Predictable Behavior**: No hidden control flow from exceptions
5. **Observability at Scale**: Pipeline builds capture and persist errors as artifacts, preventing build halts while ensuring full traceability.

**Key Principle**: Errors are data, and data can be transformed, inspected, and recovered from.

---

## Execution Modes: Resilient vs. Fail-Fast

T-Lang provides two modes of evaluation, controlled by the "resilience" setting:

### 1. Resilient Mode (Default)
Evaluation continues even when statements or pipeline nodes result in `VError` values. This is aligned with the "Errors are Values" philosophy, allowing you to collect as much information as possible from a single run. Residual errors are simply passed to downstream functions (which may short-circuit via `|>` or recover via `?|>`). This is the recommended mode for complex data pipelines where you want to observe as many diagnostic outcomes as possible in a single pass.

### 2. Fail-Fast Mode
Evaluation stops immediately upon encountering the first `VError`. This is the usual, common behaviour for critical scripts where subsequent steps should only run if previous ones were flawlessly successful.

**How to toggle**:
- **CLI**: Use `t run --failfast script.t`
- **REPL**: Set `t_run(failfast = true, ...)`
- **Pipelines**: Use `t_make(failfast = true)`

---

---

## Error Types

T has several categories of errors:

### 1. Type Errors

Occur when operations receive incompatible types:

```t
1 + "hello"
-- Error(TypeError: Cannot add Int and String)

[1, 2] * 3
-- Error(TypeError: Cannot multiply List and Int. Hint: Use map(\(x) x * 3))
```

### 2. Name Errors

Occur when referencing undefined variables or functions:

```t
undefined_var
-- Error(NameError: 'undefined_var' is not defined)

prnt(42)
-- Error(NameError: 'prnt' is not defined. Did you mean 'print'?)
```

**Features**:
- Levenshtein distance-based suggestions
- Searches current scope and standard library
- Case-insensitive suggestions

### 3. Value Errors

Occur when values are invalid for the operation:

```t
sqrt(-1)
-- Error(ValueError: Cannot compute square root of negative number)

quantile([1, 2, 3], 1.5)
-- Error(ValueError: Quantile must be between 0 and 1)
```

### 4. Arity Errors

Occur when function calls have wrong number of arguments:

```t
add = \(a, b) a + b
add(1)
-- Error(ArityError: Expected 2 arguments (a, b) but got 1)

add(1, 2, 3)
-- Error(ArityError: Expected 2 arguments (a, b) but got 3)
```

**Features**:
- Shows expected parameter names
- Shows actual argument count
- Suggests correct usage

### 5. Division by Zero

```t
1 / 0
-- Error(DivisionByZero: Division by zero)

10 % 0
-- Error(DivisionByZero: Modulo by zero)
```

### 6. NA Errors

Occur when NA values are encountered without explicit handling:

```t
mean([1, NA, 3])
-- Error(NAError: NA value encountered. Use na_rm = true to skip NA values)

1 + NA
-- Error(TypeError: Operation on NA value)
```

### 7. Assertion Errors

Occur when assertions fail:

```t
assert(2 + 2 == 5)
-- Error(AssertionError: Assertion failed)

assert(false, "Custom message")
-- Error(AssertionError: Custom message)
```

### 8. Validation Errors

Custom errors for data validation:

```t
validate_age = \(age) 
  if (age < 0 or age > 150)
    error("ValidationError", "Age must be between 0 and 150")
  else
    age

validate_age(-5)
-- Error(ValidationError: Age must be between 0 and 150)
```

---

## Error as Values

### Creating Errors

```t
-- Generic error
err = error("Something went wrong")

-- Error with code
err = error("NotFoundError", "File not found")

-- Conditional errors
result = if (value < 0)
  error("ValueError", "Value must be positive")
else
  value
```

### Inspecting Errors

```t
result = 1 / 0

-- Check if error
is_error(result)        -- true

-- Get error code
error_code(result)      -- "DivisionByZero"

-- Get error message
error_message(result)   -- "Division by zero"

-- Get additional context
error_context(result)   -- Stack trace or additional info
```

### Error Propagation

Errors flow through computations until caught:

```t
step1 = 1 / 0                    -- Error
step2 = step1 + 10               -- Still error (no computation)
step3 = step2 * 2                -- Still error

is_error(step3)                  -- true
error_message(step3)             -- "Division by zero"
```

---

## Pipe Operators and Errors

### Conditional Pipe (`|>`)

**Short-circuits** on errors:

```t
-- Success path
5 |> \(x) x * 2 |> \(x) x + 1   -- 11

-- Error short-circuits
error("fail") |> \(x) x * 2 |> \(x) x + 1
-- Error(GenericError: fail)
-- The functions are never called
```

**Use case**: Normal data pipelines where errors should stop processing.

```t
df = read_csv("data.csv")
  |> filter($age > 0)
  |> select($name, $age)
  |> arrange($age)
-- If read_csv fails, rest of pipeline is skipped
```

### Maybe-Pipe (`?|>`)

**Always forwards** values, including errors:

```t
-- Success path (same as |>)
5 ?|> \(x) x * 2                 -- 10

-- Error is forwarded to function
error("fail") ?|> \(x) 
  if (is_error(x)) 0 else x      -- 0 (recovered!)
```

**Use case**: Error recovery, fallback values, logging.

```t
-- Recovery pattern
result = risky_operation()
  ?|> \(x) if (is_error(x)) {
    print(str_join(["Error occurred: ", error_message(x)]))
    default_value
  } else {
    x
  }

-- Chain recovery with normal processing
error("fail")
  ?|> \(x) if (is_error(x)) 0 else x  -- Recovery
  |> \(x) x + 1                        -- Normal processing (1)
```

---

## Pattern Matching and Errors

Pattern matching is the most declarative way to handle first-class errors in T. It allows you to destructure error values and branch logic based on specific outcomes.

### Basic Error Matching

Use the `Error { msg }` pattern to capture the error message:

```t
result = match(1 / 0) {
  Error { msg: m } => str_sprintf("Caught error: %s", m),
  val => str_sprintf("Result: %f", val)
}
-- "Caught error: Division by zero"
```

### Automatic Error Propagation

If you don't explicitly handle `Error` in a `match` expression, the original error value is propagated automatically. This matches the behavior of the standard pipe (`|>`).

```t
-- This match does NOT handle Error
res = match(error("Fail")) {
  [head, ..tail] => head,
  [] => 0
}
-- Result is still Error("Fail")
```

---

## Error Recovery Patterns

### Pattern 1: Default Values

```t
-- Return default on error using match
safe_divide = \(a, b)
  match(a / b) {
    Error { _ } => 0.0,
    res => res
  }

safe_divide(10, 0)   -- 0.0
safe_divide(10, 2)   -- 5.0
```

### Pattern 2: Fallback Sources

```t
-- Try multiple data sources cleanly
data = match(read_csv("primary.csv")) {
  Error { _ } => match(read_csv("backup.csv")) {
    Error { _ } => read_csv("fallback.csv"),
    res => res
  },
  res => res
}

-- Or combining match with the maybe-pipe for flat recovery
final_data = read_csv("primary.csv")
  ?|> \(res) match(res) {
    Error { _ } => read_csv("backup.csv"),
    valid_df => valid_df
  }
```

### Pattern 3: Validation and Recovery

```t
-- Validate, recover if invalid
process_value = \(v)
  if (v < 0)
    error("ValueError", "Negative value")
  else if (is_na(v))
    error("NAError", "NA value")
  else
    v * 2

-- Recover from validation errors
safe_process = \(v)
  process_value(v) ?|> \(result)
    if (is_error(result)) {
      print(str_sprintf("Invalid value: %s", error_message(result)))
      0  -- Default
    } else {
      result
    }

safe_process(-5)   -- Prints error, returns 0
safe_process(10)   -- Returns 20
```

### Pattern 4: Error Logging

```t
-- Log errors and continue
logged_operation = risky_function()
  ?|> \(x) if (is_error(x)) {
    write_log(str_sprintf("Error in risky_function: %s", error_message(x)))
    x  -- Pass error along
  } else {
    x
  }

-- Or convert to success after logging
logged_with_default = logged_operation
  ?|> \(x) if (is_error(x)) default_value else x
```

### Pattern 5: Partial Success

```t
-- Process list, collecting errors
process_many = \(items)
  map(items, \(item)
    process_item(item) ?|> \(result)
      if (is_error(result))
        {success: false, error: error_message(result)}
      else
        {success: true, value: result}
  )

results = process_many([1, -2, 3, 0])
-- [
--   {success: true, value: 2},
--   {success: false, error: "Negative value"},
--   {success: true, value: 6},
--   {success: false, error: "Division by zero"}
-- ]

-- Filter successes
successes = filter(results, \(r) r.success)
```

### Pattern 6: Error Transformation

Pattern matching is excellent for converting low-level errors into domain-specific ones.

```t
-- Transform errors using match
enhance_error = \(e)
  match(e) {
    Error { msg } => 
      if (str_detect(msg, "DivisionByZero"))
        error("MathError", str_sprintf("Calculation failed: %s", msg))
      else if (str_detect(msg, "NAError"))
        error("DataQualityError", str_sprintf("Quality issue: %s", msg))
      else
        e,
    _ => e
  }

risky_calc() ?|> enhance_error
```

---

## Pipeline Diagnostics and Soft-Failures

In T-Lang, the materialization of a pipeline is a separate phase from the logic execution. When a node in a pipeline fails, it doesn't necessarily halt the entire build.

### Hard-Fail vs. Soft-Fail

1.  **Hard-Fail**: Occurs when the environment or system fails (e.g., missing dependencies, Nix build errors, out-of-memory). The build stops immediately and no artifacts are produced.
2.  **Soft-Fail (Captured Error)**: Occurs when the node's internal code (T, Python, or R) raises an error. The node produces a `VError` artifact instead of the expected data. The pipeline build **continues**, allowing other independent branches to complete.

### The Build Summary

After a build, T provides an iconographic summary:

```text
✖ Pipeline build captured node errors [5 succeeded, 2 captured errors, 2 had warnings]
  ! Captured error in node: r_err
  ! Captured error in node: py_err
  ? Warnings in node: r_warn
  ? Warnings in node: py_warn
```

- **`!` (Captured error)**: The node failed, producing a `VError` artifact.
- **`?` (Warnings)**: The node succeeded, but issued non-terminal diagnostics.

### Investigating with `explain()`

When you load a node that soft-failed, you receive a T-Lang Error object. You can use the `explain()` builtin to see the exact cause, including tracebacks from other languages.

```t
hu = read_node("py_err")
-- Error(RuntimeError: "Critical error in Python logic")

explain(hu)
-- Output:
-- Context:
--   runtime_traceback: "Traceback (most recent call last): ..."
--   node_name: "py_err"
--   node_status: "errored"
```

---

## Polyglot Error Handling (Python/R)

T-Lang provides a "diagnostic bridge" for nodes running in other languages.

### Python Nodes
- **Exceptions**: All uncaught exceptions are caught by the T-Lang runner. The exception type, message, and full traceback are serialized into the `VError` artifact.
- **Warnings**: Captured via `warnings.catch_warnings()`. These are listed in the build summary but do not cause the node to return an error state.

### R Nodes
- **Errors**: Handled via `tryCatch`. R conditions are mapped to `VError` codes.
- **Warnings**: Handled via `withCallingHandlers`. Warnings are collected into the node's metadata without interrupting the primary data export.

---

### Pattern 7: Conditional Modeling and Automated Reporting

In automated daily pipelines where data is refreshed externally, a three-way branching strategy is often necessary. You can use pattern matching to choose between a full complex model, a simplified fallback model, or a validation report based on the data's characteristics.

```t
p = pipeline {
  -- 1. Load the latest daily raw data
  raw_data = node(command = read_csv("daily_extract.csv"))

  -- 2. Validate and "tag" the data based on quality metrics
  quality_status = node(command = 
    raw_data ?|> \(df) {
      if (nrow(df) < 500) 
        error("CriticalError", "Insufficient rows for any modeling.")
      else if (length(levels(df.segment)) < 2)
        [type: "low_diversity", data: df]
      else
        [type: "high_quality", data: df]
    }
  )

  -- 3. Precise branching: Choose the best action for each state
  final_result = node(command = 
    quality_status ?|> \(outcome) match(outcome) {
      -- Full Case: Sufficient data and factor levels
      [type: "high_quality", data: df] => 
        lm(df, $yield ~ $temp + $segment),
      
      -- Fallback Case: Enough data, but not enough factor diversity
      -- We drop the 'segment' predictor to avoid model failure
      [type: "low_diversity", data: df] => 
        lm(df, $yield ~ $temp),
      
      -- Failure Case: Stop modeling and generate a diagnostic report
      Error { msg } => 
        generate_validation_report(msg, raw_data)
    }
  )
}
```

**Why use this?**:
*   **Adaptive Modeling**: Your pipeline automatically scales its complexity to match the quality of the incoming data, avoiding "singular matrix" or "one level factor" errors.
*   **Operational Intelligence**: Instead of the whole pipeline failing due to a minor data shift (like one category disappearing from today's extract), the system gracefully degrades its service while still providing a result.
*   **Auditability**: Every run clearly states which path was taken through the use of descriptive tags like `low_diversity` or `high_quality`.

---

## Comparing Error Handling Tools

T offers several tools for managing errors, each suited for different scenarios:

*   **Conditional Pipe (`|>`)**: Best for "fail-fast" pipelines where any error should immediately stop further processing. It's the default for sequential operations.
*   **Maybe-Pipe (`?|>`)**: Ideal for scenarios requiring explicit error handling or recovery at each step. It allows functions to receive and act upon error values, enabling logging, fallback logic, or transformation.
*   **Pattern Matching (`match`)**: The most declarative and powerful tool for branching logic based on error types or success values. It's excellent for:
    *   **Specific Error Recovery**: Handling different error types differently.
    *   **Default Values/Fallbacks**: Providing alternative values when an error occurs.
    *   **Error Transformation**: Converting generic errors into more domain-specific ones.
    *   **Complex Recovery Logic**: When `if (is_error(x))` becomes too nested or less readable.

**General Guidance**:
*   Use `|>` for the majority of your data pipelines where you expect success and want to stop on the first error.
*   Use `?|>` when you need to inspect or act on an error *at a specific point* in a pipeline, often followed by `match` or an `if (is_error(...))` check.
*   Use `match` when your error recovery logic involves different actions for different error types, or when you want a clear, declarative way to distinguish between success and various error states.

---

## Common Errors

### NA Handling Errors

**Problem**: Forgot to handle NA values

```t
mean([1, 2, NA, 4])
-- Error(NAError: NA value encountered)
```

**Solution**: Use `na_rm = true`

```t
mean([1, 2, NA, 4], na_rm = true)  -- 2.33...
```

### Type Mismatch Errors

**Problem**: Mixing incompatible types

```t
"Age: " + 25
-- Error(TypeError: Cannot add String and Int)
```

**Solution**: Use separate print statements (alpha does not have string conversion yet)

```t
-- Workaround for output:
print("Age: ")
print(25)

-- Or use R/Python for formatting if needed
```

### Empty Collection Errors

**Problem**: Operating on empty data

```t
mean([])
-- Error(ValueError: Cannot compute mean of empty list)
```

**Solution**: Check before operating

```t
safe_mean = \(data)
  if (length(data) == 0)
    error("ValueError", "Empty data")
  else
    mean(data)

-- Or use default
safe_mean_with_default = \(data)
  if (length(data) == 0) 0.0 else mean(data)
```

### Division by Zero

**Problem**: Dividing by zero

```t
revenue_per_customer = total_revenue / customer_count
-- Error if customer_count = 0
```

**Solution**: Guard condition

```t
revenue_per_customer = if (customer_count == 0)
  0.0
else
  total_revenue / customer_count
```

### Missing Column Errors

**Problem**: Referencing non-existent column

```t
df.nonexistent_column
-- Error(NameError: Column 'nonexistent_column' not found)
```

**Solution**: Check columns first

```t
cols = colnames(df)
has_column = length(filter(cols, \(c) c == "age")) > 0

if (has_column)
  df.age
else
  error("ColumnError", "Required column 'age' not found")
```

---

## Best Practices

### 1. Fail Fast, Fail Explicitly

**Good**: Validate inputs early

```t
process_data = \(df)
  if (nrow(df) == 0)
    error("ValidationError", "Empty dataset")
  else if (not has_required_columns(df))
    error("ValidationError", "Missing required columns")
  else
    -- Process data
```

**Bad**: Silent failures

```t
process_data = \(df)
  -- Assumes data is valid, may fail later
  df |> filter(...) |> summarize(...)
```

### 2. Use Descriptive Error Messages

**Good**: Clear, actionable messages

```t
if (age < 0 or age > 150)
  error("ValidationError", str_sprintf("Age must be between 0 and 150, got: %s", str_string(age)))
```

**Bad**: Vague messages

```t
if (age < 0 or age > 150)
  error("Invalid age")
```

### 3. Choose the Right Pipe

**Use `|>`** for normal success paths:
```t
df |> filter($active) |> select($name)
```

**Use `?|>`** for error recovery:
```t
load_data() ?|> \(x) if (is_error(x)) backup_data() else x
```

### 4. Document Error Conditions

```t
-- Computes mean, errors if list is empty or contains NA
-- Use na_rm = true to skip NA values
my_mean = \(values, na_rm)
  if (length(values) == 0)
    error("ValueError", "Empty list")
  else
    -- Implementation
```

### 5. Test Error Cases

```t
-- Test successful case
assert(safe_divide(10, 2) == 5.0)

-- Test error recovery
assert(safe_divide(10, 0) == 0.0)
assert(is_error(risky_function(-1)))
```

### 6. Log Errors in Production

```t
production_pipeline = pipeline {
  data = read_csv("data.csv") ?|> \(x) if (is_error(x)) {
    write_log(str_sprintf("CRITICAL: Failed to load data: %s", error_message(x)))
    x
  } else x
  
  -- Rest of pipeline with error handling
}
```

### 7. Avoid Deep Nesting

**Bad**: Deeply nested error checks

```t
result = if (is_error(step1))
  handle_step1_error(step1)
else
  if (is_error(step2))
    handle_step2_error(step2)
  else
    if (is_error(step3))
      handle_step3_error(step3)
    else
      success_value
```

**Good**: Use maybe-pipe for flat composition

```t
result = step1
  ?|> \(x) if (is_error(x)) handle_step1_error(x) else step2(x)
  ?|> \(x) if (is_error(x)) handle_step2_error(x) else step3(x)
  ?|> \(x) if (is_error(x)) handle_step3_error(x) else x
```

---

## Debugging Errors

### Print Error Details

```t
result = risky_operation()

if (is_error(result)) {
  print(str_sprintf("Error code: %s", error_code(result)))
  print(str_sprintf("Error message: %s", error_message(result)))
  print(str_sprintf("Error context: %s", error_context(result)))
}
```

### Trace Error Source

```t
-- Add markers in pipeline
step1 = operation1() ?|> \(x) if (is_error(x)) {
  print("Error at step1")
  x
} else x

step2 = operation2(step1) ?|> \(x) if (is_error(x)) {
  print("Error at step2")
  x
} else x
```

### Assert Invariants

```t
-- Use assertions to catch logic errors
result = computation()
assert(result > 0, "Result should be positive")
assert(length(result_list) == expected_length, "Length mismatch")
```

---

**See Also**:
- [Examples](examples.md) — Error handling patterns in practice
- [API Reference](api-reference.md) — Error-related functions
- [Troubleshooting](troubleshooting.md) — Common issues and solutions

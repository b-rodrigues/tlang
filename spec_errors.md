### Analysis of the "Print-and-Return-None" Model

*   **Proposal:** `x = sqrt(-1)` prints `"Can't compute..."` and `x` becomes `None`.
*   **Strength:** It's very simple for the interactive REPL user. They get immediate feedback.
*   **Fatal Flaw:** The error message is completely disconnected from the result. The value `None` contains no information about *why* the operation failed. A program cannot distinguish between `sqrt(-1)` and `read_csv("missing.csv")`. Both just produce `None`, making it impossible to handle different errors in different ways. This prevents programmatic error handling.

Your instinct about `.errormsg` is the key to solving this. If a value needs to carry an error message, it **cannot be `None`**. It must be a different kind of object: an **Error object**.

This leads us to the "errors as values" philosophy, which is the gold standard for robust functional programming and data pipelines.

---

### The Best UX: First-Class Error Values

The most powerful and user-friendly system is to treat errors as their own special, structured data type. This gives the user full control.

#### 1. Creation: Errors are Values
When an operation fails, it returns an `Error` value. This value is a piece of data, just like a number or a string.

```t
-- This does NOT print anything.
-- It returns a value and assigns it to x.
x = sqrt(-1)

-- x now holds the value: Error({message: "Domain Error: Cannot compute...", code: 101})
```

#### 2. Checking: A Simple Predicate
The user needs an easy way to check if a result was successful. A built-in function is the cleanest way.

```t
y = some_operation()

if is_error(y) {
  -- ... handle the error ...
} else {
  -- ... use the successful result ...
}```

#### 3. Programmatic Handling: Accessing Metadata
This is the feature you correctly identified as necessary. An `Error` value is a structured object (like a `Dict`), so you can access its contents using dot notation.

```t
if is_error(y) {
  -- The user decides WHEN and HOW to show the error.
  print("Operation failed! Reason: " + y.message)

  -- The user can even react to specific error codes.
  if y.code == 404 {
    print("File was not found.")
  }
}
```

#### 4. Propagation: Errors "Poison" Pipelines
`Error` values automatically propagate through computations. The `Error` value is passed along, and subsequent operations do nothing. This keeps pipelines clean.

```t
-- The sqrt() fails and returns an Error value.
-- The `+ 5` and `* 10` operations see the Error and just pass it through.
-- The final result is the ORIGINAL Error from sqrt().
result = sqrt(-1) + 5 * 10

print(result)
-- Output: Error: Domain Error: Cannot compute the square root of a negative number.
```

#### 5. Display: The REPL and `print()` are Error-Aware
The REPL and the `print()` function know how to format `Error` values nicely. They are only displayed when the user explicitly asks to see the value. This puts the user in control and avoids noisy, unexpected output during a long pipeline run.

---

### Specification Paragraph for Easy Copy & Pasting

Here is a paragraph for your specification that formalizes this superior "First-Class Error Value" model.

---

### Error Semantics: Errors as First-Class Values

T handles runtime failures using a "first-class error value" model. Instead of throwing exceptions or returning a simple `Null`/`None` value, a failed operation returns a structured `Error` object. This value contains metadata about the failure, such as a descriptive `.message` and an optional `.code`, making errors fully programmable. This approach ensures that no information is lost and gives the user complete control over error handling. Errors propagate ("poison") subsequent operations in a pipeline, and are only displayed when explicitly printed, preventing unexpected side effects. A built-in predicate, `is_error(x)`, allows for robust, programmatic checking and handling of failures. 

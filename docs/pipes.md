# The Pipe Operator (`|>`)

The pipe operator `|>` is the primary way to structure data-driven logic in T-Lang. It enables a clean, top-to-bottom flow that transforms data step-by-step.

## Philosophy: Monadic vs. Transparent

In T-Lang, errors are values, which raises a design question: *Should a pipe always pass the input along, even if it's an error?*

T-Lang implements the **Short-circuiting Pipe** by default.

### 1. Simple Forwarding (`|>`)
When using the standard pipe, T-Lang provides **Railway Oriented Programming** semantics.

- **If the input is Data**: It calls the function.
- **If the input is an Error**: It **short-circuits**. The function is never called, and the error is passed directly to the next stage.

```t
-- If read_csv fails, filter and select are never even attempted.
df = read_csv("missing.csv") 
  |> filter($age > 20)
  |> select($name)
-- Output: Error(FileError: "File not found")
```

**Why this design?**
1. **Reduce Noise**: It prevents a single failure from cascading into hundreds of confusing "Type Errors" downstream.
2. **Performance**: It avoids spinning up expensive resources (like JVMs or Python handlers) if the data flow is already broken.
3. **Happy Path**: It allows you to write the "Success Path" without littering your code with `if (is_error(x))` checks at every line.

### 2. Transparent Forwarding (`?|>`)
If you **want** to handle errors within the pipe (e.g., to log them or provide a default value), use the **Maybe-Pipe** `?|>`. This operator always forwards the value, even if it is an Error.

```t
read_csv("config.csv")
  ?|> \(v) if (is_error(v)) { default_config } else { v }
  |> validate_config()
```

## Function Calls vs. Pipes

It is important to note the difference between piping and direct function calls:

- **Function Calls `f(x)`**: Are **Transparent**. The function is always invoked with the argument. The function's internal logic then decides whether to propagate the error or handle it.
- **Pipe Stages `x |> f()`**: Are **Monadic**. The language engine intercepts the Error and skips the call entirely.

### Example
```t
e = error("stop")

-- Transparent call
is_error(e)   -- Returns true (the function runs)

-- Monadic pipe
e |> is_error() -- Returns Error("stop") (short-circuited, function never runs!)
```

## Summary
| Operator | Type | Error Behavior | Use Case |
| :--- | :--- | :--- | :--- |
| `|>` | Standard Pipe | **Short-circuit** | Normal data wrangling pipelines. |
| `?|>` | Maybe Pipe | **Transparent** | Error recovery, logging, and fallback logic. |
| `f(x)` | Function Call | **Transparent** | Builtin diagnostics and explicit error handling. |

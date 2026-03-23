Excellent. A consistent error style is a **language design feature**, not a UX afterthought.

Below is a **Global Error Style Guide for T**, written so your engineers can implement it consistently and maintain it long-term.

---

# T Error Message Style Guide

## Core Principles

1. **State what failed**
2. **State why it failed**
3. **State what the user can do instead (when obvious)**
4. Never expose interpreter internals
5. Never blame the user
6. Never be vague

Errors must teach the language model.

---

# 1. Canonical Structure

All runtime errors must follow this structure:

```
Error(<ErrorKind>): <Short summary sentence>.
<Optional clarification sentence>.
<Optional Hint: ...>
```

Example:

```
Error(TypeError): Operator `|` expects Bool and Bool.
Hint: Use `.|` for element-wise boolean operations.
```

---

# 2. Error Categories (Stable Public API)

Use only these categories:

* `TypeError`
* `NameError`
* `ArityError`
* `ValueError`
* `IndexError`
* `MatchError`
* `SyntaxError`
* `InternalError` (never shown in normal user code)

Do NOT invent ad-hoc error types.

---

# 3. Tone Rules

### Use:

* Declarative language
* Precise type names (`Bool`, `Int`, `List`)
* Backticks around operators and identifiers

### Do NOT use:

* “Cannot”
* “Invalid”
* “Oops”
* Implementation terms (AST, runtime, variant, etc.)
* Words like “bitwise” unless it is part of user-level language

Instead of:

```
Cannot bitwise or Bool and List
```

Use:

```
Operator `|` expects Bool and Bool.
```

Clear. Formal. Neutral.

---

# 4. Operator Errors

## 4.1 Scalar Operator Type Errors

Format:

```
Error(TypeError): Operator `<op>` expects <Type1> and <Type2>.
```

If broadcast alternative exists:

```
Hint: Use `.<op>` for element-wise operations.
```

Example:

```
Error(TypeError): Operator `&` expects Bool and Bool.
Hint: Use `.&` for element-wise boolean operations.
```

---

## 4.2 Broadcast Length Mismatch

```
Error(ValueError): Broadcast requires lists of equal length.
Left has length 2, right has length 3.
```

Always include lengths. Never hide numbers.

---

## 4.3 Short-Circuit Misuse

If user tries:

```
.&&
```

Use:

```
Error(SyntaxError): `&&` is a short-circuit operator and cannot be broadcasted.
```

Clear semantic explanation.

---

# 5. Function Errors

## 5.1 Arity

```
Error(ArityError): Function `f` expects 2 arguments but received 3.
```

Always show expected and received.

---

## 5.2 Non-callable

```
Error(TypeError): Value of type Int is not callable.
```

Never say “not a function”. Use type name.

---

# 6. If Expression Errors

If condition is not Bool:

```
Error(TypeError): `if` condition must be Bool.
Received List.
```

Short. Direct.

---

# 7. Indexing Errors

Out of bounds:

```
Error(IndexError): Index 5 is out of bounds for List of length 3.
```

Never hide the length.

---

# 8. Name Resolution Errors

```
Error(NameError): Name `x` is not defined.
```

No extra commentary.

---

# 9. Pattern Matching Errors (Future-Proofing)

```
Error(MatchError): Non-exhaustive pattern match.
```

If possible, show unmatched value type.

---

# 10. Consistency Rules

### Always:

* Capitalize type names: `Bool`, `Int`, `List`
* Wrap operators in backticks: `+`, `&&`
* End sentences with periods
* Use singular form in summaries

### Never:

* Use lowercase type names
* Use stack traces by default
* Show OCaml exception names

---

# 11. Error Length Guidelines

* First line: ≤ 80 characters
* Maximum 3 lines total
* Hint only when action is obvious

Do not over-explain.

---

# 12. Internal Errors

If something impossible happens:

```
Error(InternalError): Unexpected operator state.
```

This should only occur during development, not user code.

---

# 13. Example: Final Polished Output

### Case 1

```
T> true | [true, false]

Error(TypeError): Operator `|` expects Bool and Bool.
Hint: Use `.|` for element-wise boolean operations.
```

---

### Case 2

```
T> [1,2] .+ [1]

Error(ValueError): Broadcast requires lists of equal length.
Left has length 2, right has length 1.
```

---

### Case 3

```
T> if ([true]) 1 else 2

Error(TypeError): `if` condition must be Bool.
Received List.
```

---

# 14. Engineering Enforcement Strategy

To keep this maintainable:

1. Centralize error construction in one module:

   ```
   Error.ml
   ```

2. Provide constructors:

```ocaml
val type_error : string -> error
val value_error : string -> error
val arity_error : string -> error
...
```

3. Never raise raw exceptions in evaluator.
4. Never build error strings inline in evaluation logic.
5. All error text defined in one file.

This prevents message drift across the codebase.

---

# 15. Long-Term Payoff

With this system:

* Errors become part of the language identity.
* Documentation examples match runtime output.
* Refactoring operators does not break error consistency.
* Contributors cannot accidentally invent new styles.

---

If you want next, I can:

* Write a concrete `Error.ml` design for you
* Or propose a structured error type that supports future IDE integration

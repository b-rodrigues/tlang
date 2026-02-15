# Scalar vs. Vector Operators: Strict Semantics

## Overview

In this language, arithmetic operators such as `+`, `-`, `*`, `/`, and `^` are **strictly scalar operators**.

They **must not** operate on vectors, lists, arrays, or other collection types.

Attempting to apply scalar operators to collections is a **type error**.

Element-wise (broadcasted) operations must be expressed explicitly using dotted operators such as:

* `.+`
* `.-`
* `.*`
* `./`
* `.^`

This rule is intentional and fundamental to the language design. It must not be relaxed.

---

## Rule

### 1. Scalar Operators

The following operators are defined **only for scalar–scalar operations**:

```
+  -  *  /  ^  %  <  >  <=  >=
```

Valid:

```
2 + 3        # 5
4 * 10       # 40
```

Invalid:

```
2 + [1, 3]        # ERROR
[1, 2] + [3, 4]   # ERROR
```

These cases must produce a type error.

---

### 2. Broadcast Operators

Element-wise operations must use dotted operators:

```
.+  .-  .*  ./  .^
```

Examples:

```
2 .+ [1, 3]        # [3, 5]
[1, 2] .+ [3, 4]   # [4, 6]
[1, 2] .* 10       # [10, 20]
```

Broadcasting is always explicit.

---

## Rationale

### 1. Eliminate Ambiguity

Overloading `+` to mean both scalar addition and vector broadcasting introduces ambiguity:

* Is `[1,2] + [3,4]` element-wise?
* Is it concatenation?
* Is it linear algebra?
* Is it broadcasting?

By forbidding collection operands for scalar operators, the language:

* Removes ambiguity
* Avoids hidden coercions
* Prevents accidental performance traps

---

### 2. Prevent Silent Bugs

Implicit broadcasting often hides errors:

```
x = 2
y = [1, 3]
z = x + y   # silently broadcasts in many languages
```

If the programmer intended scalar logic, this becomes a silent semantic shift.

Requiring `.+` makes intent explicit:

```
z = x .+ y
```

No silent behavior changes are possible.

---

### 3. Preserve Algebraic Meaning

`+` remains mathematically scalar.

Collections are not numbers.

This preserves:

* Type clarity
* Predictable operator meaning
* Cleaner type checking
* Simpler compiler/interpreter implementation

---

### 4. Improve Readability

Compare:

```
a + b
```

versus

```
a .+ b
```

The dotted operator signals clearly:

> This is a broadcasted, element-wise operation.

Readers immediately understand the semantics.

---

## Type System Requirement

The interpreter or compiler must enforce:

```
if (left is Collection) OR (right is Collection)
    and operator is scalar operator
then
    raise TypeError
```

This is non-negotiable.

There must be no implicit lifting or coercion of scalars to vectors for scalar operators.

---

## Error Message Specification

When violated, the system should produce a clear and instructive error:

Example:

```
TypeError: Operator '+' is defined for scalars only.
Use '.+' for element-wise (broadcast) operations.
```

The error must:

1. Identify the operator.
2. State that it is scalar-only.
3. Suggest the dotted alternative.

---

## Explicit Design Principle

> Broadcasting must always be explicit.

Scalar operators are scalar.
Broadcast operators are broadcast.

The language does not guess user intent.

---

## Guidance for Tooling and LLMs

This rule is fundamental and must not be altered by:

* Code generators
* Refactoring tools
* Auto-formatters
* AI code assistants
* LLM-based transpilers

### DO NOT:

* Rewrite `a + b` into broadcast automatically.
* Assume `+` should work on vectors.
* Introduce implicit broadcasting for convenience.
* Emulate semantics from other languages.

### ALWAYS:

* Use dotted operators for element-wise behavior.
* Preserve strict scalar-only semantics of `+`, `-`, etc.

If generating code involving collections, use `. +`-style operators explicitly.

---

## Summary

| Operation Type | Operator | Works On        | Allowed |
| -------------- | -------- | --------------- | ------- |
| Scalar         | `+`      | Scalar          | Yes     |
| Scalar         | `+`      | Vector          | No      |
| Broadcast      | `.+`     | Vector          | Yes     |
| Broadcast      | `.+`     | Scalar + Vector | Yes     |

This design ensures:

* Explicitness
* Safety
* Clarity
* Predictable semantics
* Robust static and dynamic analysis

This rule is part of the language contract and must remain stable.

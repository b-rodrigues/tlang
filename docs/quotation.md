# Metaprogramming: Quotation and Quasiquotation

T provides powerful metaprogramming capabilities inspired by Lisp and R's `rlang` package. These features allow you to capture code as data, manipulate it, and evaluate it dynamically.

## Core Concepts

- **Quotation**: Capturing an expression without evaluating it immediately.
- **Unquoting**: Selectively evaluating parts of a quoted expression.
- **Splicing**: Expanding a list or collection into multiple arguments or elements within a quoted expression.
- **Symbols**: Representing names (identifiers) as data.

## Capturing Code

### `expr(expression)`

The `expr()` function captures the code you provide as an **Expression** object.

```t
e = expr(1 + 2)
print(e)
-- Output: expr(1 + 2)
```

Unlike regular functions, `expr()` is a special form that does not evaluate its argument.

### `exprs(...)`

`exprs()` captures multiple expressions and returns them as a list of Expression objects. It supports named arguments.

```t
ee = exprs(x = 1 + 1, y = 2 + 2)
-- Result: [x: expr(1 + 1), y: expr(2 + 2)]
```

### Symbols and Bare Words

In T, if you use a word that isn't defined as a variable, it is automatically treated as a **Symbol** when inside a quoting context. This is useful for building Domain Specific Languages (DSLs).

```t
e = expr(select(df, age, height))
-- 'select', 'age', and 'height' are captured as symbols.
```

## Evaluating Code

### `eval(expr_object)`

The `eval()` function takes an Expression object and evaluates it in the current environment.

```t
e = expr(10 + 20)
res = eval(e)
print(res) -- Output: 30
```

## Quasiquotation

Quasiquotation allows you to "fill in the blanks" in a captured expression.

### `!!` (Unquote)

The `!!` (pronounced "bang-bang") operator evaluates its operand immediately and injects the result into the surrounding quoted expression.

```t
x = 10
e = expr(1 + !!x)
print(e) 
-- Output: expr(1 + 10)
```

If you unquote another Expression object, it is merged directly into the AST:

```t
inner = expr(1 + 1)
outer = expr(2 * !!inner)
print(outer)
-- Output: expr(2 * (1 + 1))
```

### `!!!` (Unquote-Splice)

The `!!!` (pronounced "triple-bang") operator evaluates its operand and **splices** the elements into the surrounding call or list. The operand must evaluate to a `List`, `Vector`, or `Dict`.

#### Splicing into Arguments

```t
vals = [1, 2, 3]
e = expr(sum(!!!vals))
print(e)
-- Output: expr(sum(1, 2, 3))
```

#### Splicing with Names

If you splice a named List, the names are used as argument names in the resulting call.

```t
my_args = [x: 10, y: 20]
e = expr(f(!!!my_args, z: 30))
print(e)
-- Output: expr(f(x = 10, y = 20, z = 30))
```

## Advanced Examples

### Dynamic Pipeline Generation

You can use quasiquotation to dynamically build pipeline nodes or intents:

```t
var_name = "mpg"
my_intent = expr(intent {
  target = !!var_name
  method = "lm"
})

print(my_intent)
-- Output: expr(intent { target = "mpg"; method = "lm" })
```

### Prefix-Call Syntax

T also supports a Lisp-style prefix call syntax which integrates seamlessly with quotation:

```t
e = expr((add, 1, 2))
-- Equivalent to expr(add(1, 2))
```

## Summary of Operators

| Operator/Function | Purpose |
| :--- | :--- |
| `expr(x)` | Capture `x` as an Expression. |
| `exprs(...)` | Capture multiple expressions as a List. |
| `eval(e)` | Evaluate Expression `e`. |
| `!!x` | Evaluate `x` and inject into `expr()`. |
| `!!!x` | Evaluate `x` and splice elements into `expr()`. |

# Metaprogramming: Quotation and Quasiquotation

T provides powerful metaprogramming capabilities inspired by Lisp and R's `rlang` package. These features allow you to capture code as data, manipulate it, and evaluate it dynamically.

## Core Concepts

- **Quotation**: Capturing an expression without evaluating it immediately.
- **Quosure**: A quoted expression paired with its lexical environment (like R's `rlang::quo`).
- **Unquoting**: Selectively evaluating parts of a quoted expression.
- **Splicing**: Expanding a list or collection into multiple arguments or elements within a quoted expression.
- **Symbols**: Representing names (identifiers) as data.

## Capturing Code: `expr` vs `quo`

T has two families of quotation functions, matching R's `rlang`:

| Function | Result | Environment | Use when… |
|----------|--------|-------------|-----------|
| `expr(x)` | `Expression` | None | You only need the AST |
| `quo(x)` | `Quosure` | Captured at call site | You need the AST + its lexical context |
| `exprs(...)` | `List[Expression]` | None | Multiple naked expressions |
| `quos(...)` | `List[Quosure]` | Captured at call site | Multiple expressions with lexical context |

### `expr(expression)`

The `expr()` function captures the code as a naked **Expression** object. The current environment is *not* stored.

```t
e = expr(1 + 2)
print(e)
-- Output: expr(1 + 2)
```

### `quo(expression)`

The `quo()` function captures the code as a **Quosure** — a pair of the expression and its lexical environment. When later evaluated with `eval()`, the expression runs in the captured environment, not the caller's.

```t
x = 10
q = quo(1 + x)   -- captures x = 10 in the environment
x = 99
eval(q)           -- returns 11, not 100
```

### `exprs(...)`

`exprs()` captures multiple expressions and returns them as a list of naked Expression objects. It supports named arguments.

```t
ee = exprs(x = 1 + 1, y = 2 + 2)
-- Result: [x: expr(1 + 1), y: expr(2 + 2)]
```

### `quos(...)`

`quos()` captures multiple expressions as a list of Quosures, each paired with the current lexical environment.

```t
x = 10
qs = quos(a = 1 + x, b = 2 * x)
-- Result: [a: quo(1 + x), b: quo(2 * x)]
-- Both quosures capture x = 10 in their environment.
```

### Symbols and Bare Words

In T, if you use a word that isn't defined as a variable, it is automatically treated as a **Symbol** when inside a quoting context. This is useful for building Domain Specific Languages (DSLs).

```t
e = expr(select(df, age, height))
-- 'select', 'age', and 'height' are captured as symbols.
```

## Evaluating Code

### `eval(expr_or_quosure)`

The `eval()` function evaluates an Expression or Quosure:
- **Expression**: evaluated in the *current* environment.
- **Quosure**: evaluated in its *captured* environment.

```t
e = expr(10 + 20)
eval(e)          -- evaluates in current env → 30

x = 5
q = quo(x + 1)   -- captures x = 5
x = 100
eval(q)          -- evaluates in captured env (x = 5) → 6
```

## Quasiquotation

Quasiquotation allows you to "fill in the blanks" in a captured expression.

### `!!` (Unquote)

The `!!` (pronounced "bang-bang") operator evaluates its operand immediately and injects the result into the surrounding quoted expression. When the operand is a Quosure, only the expression part is injected (the environment is stripped).

```t
x = 10
e = expr(1 + !!x)
print(e) 
-- Output: expr(1 + 10)
```

```t
inner = quo(1 + 1)
outer = expr(2 * !!inner)   -- !! strips env from quosure
print(outer)
-- Output: expr(2 * (1 + 1))
```

### `!!!` (Unquote-Splice)

The `!!!` (pronounced "triple-bang") operator evaluates its operand and **splices** the elements into the surrounding call or list. The operand must evaluate to a `List`, `Vector`, or `Dict`. Quosures in the spliced list have their environments stripped.

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

### `!!name := value` (Dynamic Naming)

The `!!name := value` syntax allows you to use a dynamically computed string or symbol as the name of an argument or list element inside a quoting context. The left-hand side (`name`) must evaluate to a `String` or `Symbol`.

```t
col = "age"
e = expr(mutate(df, !!col := 42))
print(e)
-- Output: expr(mutate(df, age = 42))
```

If `!!name` does not evaluate to a `String` or `Symbol`, a `TypeError` is raised.

## Non-Standard Evaluation (NSE)

For writing functions that accept unevaluated expressions from the caller — similar to `dplyr` verbs in R — T provides `enquo()` and `enquos()`.

### `enquo(param)`

`enquo()` must be called inside a function body. It captures the **expression AND the caller's environment** for the named argument `param`, returning a Quosure. This is the quosure equivalent of `enquo()` in R's rlang.

```t
my_select = \(df: DataFrame, col: Any -> DataFrame) {
  col_expr = enquo(col)           -- captures expr + caller's env
  eval(expr(df |> select(!!col_expr)))
}

my_select(iris, $Sepal.Length)
-- Equivalent to: iris |> select($Sepal.Length)
```

`enquo()` accepts exactly one argument, which must be a bare symbol (the name of one of the function's parameters).

### `enquos(...)`

`enquos()` is the variadic counterpart to `enquo()`. It captures all expressions passed through the variadic `...` parameter as a named list of Quosures, each paired with the caller's environment.

```t
my_summarize = \(df: DataFrame, ... -> DataFrame) {
  cols = enquos(...)              -- list of quosures from the caller
  eval(expr(df |> summarize(!!!cols)))
}

my_summarize(iris,
  mean_sepal = mean($Sepal.Length),
  mean_petal = mean($Petal.Length))
-- Evaluates to: iris |> summarize(mean_sepal = ..., mean_petal = ...)
```

`enquos()` is called with `...` or with no arguments; both capture the variadic expressions from the enclosing call.

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
| `expr(x)` | Capture `x` as a naked Expression (no environment). |
| `exprs(...)` | Capture multiple expressions as a List of naked Expressions. |
| `quo(x)` | Capture `x` as a Quosure (expression + lexical environment). |
| `quos(...)` | Capture multiple expressions as a List of Quosures. |
| `eval(e)` | Evaluate Expression `e` in the current env, or Quosure `e` in its captured env. |
| `!!x` | Evaluate `x` and inject into `expr()`/`quo()`; strips env from quosures. |
| `!!!x` | Evaluate `x` and splice elements into `expr()`/`quo()`. |
| `!!name := value` | Use a dynamic String/Symbol as an argument name inside `expr()`/`quo()`. |
| `enquo(param)` | Inside a function: capture caller's expression for `param` as a Quosure. |
| `enquos(...)` | Inside a function: capture all variadic expressions as a List of Quosures. |

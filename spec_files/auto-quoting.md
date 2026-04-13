# NSE and Metaprogramming in T: Current State and Proposed Improvements

## Background

This document summarises a GitHub issue raised by Jonathan Carroll (the original author of the 2017 R-devel RFC on native unquoting) and the subsequent discussion about what T already provides, 
what the ergonomic gaps are, and what could be added.

The original RFC proposed a `@` prefix operator for R that would perform in-place unquoting of variable names, enabling patterns like:

```r
f <- function(d, col1, col2, new_col_name) {
    d %>% mutate(@new_col_name = @col1 + @col2)
}
```

The issue asked whether T could support something similar, and whether the working workaround using `enquo` and `!!` could be simplified.

---

## What T Already Has

T ships a complete quasiquotation system today. The relevant pieces are:

### Quoting and unquoting

- `expr(code)` — captures an expression without evaluating it
- `quo(code)` — captures an expression together with its lexical environment (a quosure)
- `!!x` — unquotes: evaluates `x` and injects the result into the surrounding `expr`/`quo`
- `!!!x` — unquote-splices: evaluates `x` and splices the elements into a call
- `!!name := value` — dynamic column naming: uses a computed string or symbol as an argument name

### Capturing caller expressions

- `enquo(param)` — inside a function body, captures the caller's expression for `param` as a quosure
- `enquos(...)` — captures all variadic caller expressions as a list of quosures

### Evaluation

- `eval(expr_or_quosure)` — evaluates an expression in the current environment, or a quosure in its captured environment

### Column reference syntax

- `$col` in colcraft verbs (`filter`, `mutate`, `summarize`, etc.) is T's native NSE syntax for column references and is already a `Symbol` value by the time it reaches the function body

---

## The Issue: Working Solution and Why It Is Necessary

Jonathan's working solution in T is:

```t
f := function(d, col1, col2, new_col_name) {
    eval(expr(
        d |> mutate(!!new_col_name := !!enquo(col1) + !!enquo(col2))
    ))
}
f(mtcars, $mpg, $hp, "foo")
```

This works. The `enquo` calls are not redundant — they are required. Here is why.

When the caller passes `$mpg`, `col1` receives a `Symbol` value. If you skip `enquo` and write `!!col1` directly:

```t
f = \(d, col1, col2, new_col_name) {
    eval(expr(
        d |> mutate(!!new_col_name := !!col1 + !!col2)
    ))
}
f(mtcars, $mpg, $hp, "foo")
-- Error(TypeError: "[L3:C39] Operator `+` expects Symbol and Symbol.")
```

The injected expression becomes `mutate(d, foo = $mpg + $hp)`, but at runtime `+` receives two raw `Symbol` values and errors. 
T's NSE transformation of `$col` syntax — which rewrites `$mpg + $hp` into `\(row) row.mpg + row.hp` — happens at parse time for literal `$col` syntax in source code. 
When Symbols are injected at runtime via `!!`, that parse-time rewriting has already happened and the data-masking context does not re-apply it.

`enquo(col1)` captures the quosure: the expression `$mpg` together with its lexical environment. When `!!enquo(col1)` is injected into the outer `expr` and then `eval`'d,
`mutate` receives the quosure and can resolve it correctly inside the data-masking context. The quosure carries the information that this is a deferred column reference, not a Symbol to be added as a value.

The attempt to define `@` as a user-space function:

```t
`@` = function(x) !!enquo(x)
```

cannot work because `!!` is a parser-level operator, not a runtime function — it only has meaning inside a quotation context.

---

## Gap 1: No `sym()` / `as_symbol()` Function

The issue also raised the equivalent of R's `get()`:

```r
x <- 1:10; y <- "x"
data.frame(z = get(y))
```

In T there is no direct equivalent. The natural approach would be:

```t
y = "x"
eval(expr(!!sym(y)))
```

but T does not currently expose a `sym()` (or `as_symbol()`) function that converts a string to a `Symbol`. This is a real gap. 
Without it, there is no clean way to go from a string variable holding a column name to a symbol that can be injected via `!!` into a quoted expression.

### Proposed addition

Add `sym(string) -> Symbol` to the `core` or `base` package:

```t
sym("mpg")         -- Symbol($mpg)
sym(y)             -- Symbol from the value of y

-- Usage
col_name = "salary"
df |> select(!!sym(col_name))
```

This is a small, self-contained addition with no parser changes required.

---

## Gap 2: No Auto-Quoting Parameter Annotations

The deeper ergonomic problem is that writing a reusable function that accepts column names forces callers to remember to pass `$col` rather than a bare name, 
and forces the function body to use `eval(expr(...))` machinery even for simple cases.

The R-devel thread proposed (via Michael Lawrence) annotating a formal parameter in the function signature to mark it as auto-quoting. 
T's existing `$` prefix creates a natural place for exactly this extension: if `$col` in a *call* means "treat as a column reference", 
then `$col` in a *parameter list* could mean "auto-quote this argument".

### Proposed syntax

```t
-- Current: caller must supply $col, body needs enquo or prior $ passing
my_mean = \(df, col) {
    col_expr = enquo(col)
    df |> summarize(result = mean(!!col_expr))
}
my_mean(df, $salary)     -- caller must remember $

-- Proposed: $ in parameter list marks argument as auto-quoted
my_mean = \(df, $col) {
    df |> summarize(result = mean(!!col))
}
my_mean(df, salary)      -- caller writes bare name, no $ needed
```

The symmetry mirrors the C pointer analogy noted in the original thread: `*a` in a declaration creates a pointer, `*a` in an expression dereferences it. 
Here `$col` in a declaration means "quote on the way in", `!!col` in the body means "inject the symbol".

This would make the `eval(expr(...))` wrapper unnecessary for the common case of passing through a column reference to a data verb.

### Scope and complexity

This is a parser and evaluator change, not just a library addition. It requires:

- recognising `$param` in lambda parameter lists as an annotation rather than a syntax error
- at call time, capturing the argument expression as a `Symbol` rather than evaluating it
- documenting the interaction with `enquo` (auto-quoted parameters would not need `enquo`)

It is the larger of the two proposed changes and warrants its own design discussion before implementation.

---

## Summary Table

| Feature | Status | Notes |
| :--- | :--- | :--- |
| `!!` unquote operator | ✅ Implemented | Works inside `expr()` and `quo()` |
| `!!!` splice operator | ✅ Implemented | Works on Lists and Dicts |
| `!!name := value` dynamic naming | ✅ Implemented | LHS must be String or Symbol |
| `enquo` / `enquos` | ✅ Implemented | Captures caller expressions |
| `$col` NSE in colcraft verbs | ✅ Implemented | Already a Symbol at call time |
| `eval(expr(...))` workaround | ✅ Works today | Verbose but correct |
| `sym(string) -> Symbol` | ❌ Missing | Small addition, no parser change |
| Auto-quoting parameter `$param` | ❌ Missing | Larger change, needs design work |

---

## Recommended Next Steps

1. **Immediate**: Add `sym(string) -> Symbol` to `core` or `base`. This unblocks the `get()`-style use case and is a one-function addition.

2. **Short term**: Update the metaprogramming documentation to clarify that `enquo` is not needed when callers already pass `$col` symbols, and show the simpler `!!col` pattern.

3. **Design discussion**: Open a separate issue for auto-quoting parameter annotations (`$param` in function signatures). This is the change that would most directly realise the original RFC's goal — functions that accept bare column names without any quoting machinery visible to the caller.

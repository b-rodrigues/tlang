# T Language Overview

> **Version**: Alpha 0.1  
> **Status**: Syntax and semantics frozen for alpha  

T is a functional programming language designed for declarative, tabular data manipulation. It combines the pipeline-driven style of R's tidyverse with OCaml's type discipline, producing a small, focused language for data wrangling and basic statistics.

---

## Core Concepts

### Values and Types

T supports the following value types:

| Type        | Example                  | Description                        |
|-------------|--------------------------|-------------------------------------|
| `Int`       | `42`                     | Integer numbers                     |
| `Float`     | `3.14`                   | Floating-point numbers              |
| `Bool`      | `true`, `false`          | Boolean values                      |
| `String`    | `"hello"`                | Text strings                        |
| `List`      | `[1, 2, 3]`             | Ordered, heterogeneous collections  |
| `Dict`      | `{x: 1, y: 2}`          | Key-value maps with string keys     |
| `Vector`    | Column data              | Typed arrays (from DataFrames)      |
| `DataFrame` | `read_csv("data.csv")`   | Tabular data (rows × columns)       |
| `Pipeline`  | `pipeline { ... }`       | DAG-based execution graph           |
| `Function`  | `\(x) x + 1`            | First-class functions               |
| `NA`        | `NA`                     | Explicit missing value              |
| `Error`     | `error("msg")`           | Structured error value              |
| `Null`      | `null`                   | Absence of value                    |
| `Intent`    | `intent { ... }`         | LLM-friendly metadata block         |

### Variables and Assignment

```t
x = 42
name = "Alice"
active = true
```

Variables are bound with `=`. All values are immutable.

### Arithmetic and Operators

```t
2 + 3       -- 5
10 - 3      -- 7
4 * 5       -- 20
15 / 3      -- 5
1 + 2.5     -- 3.5 (mixed int/float is promoted)
"hi" + " T" -- "hi T" (string concatenation)
```

Operator precedence follows standard mathematical conventions. Parentheses override precedence.

### Comparisons

```t
5 == 5    -- true
5 != 3    -- true
3 < 5     -- true
5 > 3     -- true
5 >= 5    -- true
2 <= 2    -- true
```

### Boolean Logic

```t
true and true   -- true
true and false  -- false
false or true   -- true
not true        -- false
```

---

## Functions

### Lambda Syntax

T supports two equivalent function definition syntaxes:

```t
-- R-style lambda (preferred)
square = \(x) x * x

-- function keyword
square = function(x) x * x
```

### Multi-Argument Functions

```t
add = \(a, b) a + b
add(3, 7)  -- 10
```

### Closures

Functions capture their enclosing environment:

```t
make_adder = \(n) \(x) x + n
add5 = make_adder(5)
add5(10)  -- 15
```

### Higher-Order Functions

```t
numbers = [1, 2, 3, 4, 5]
map(numbers, \(x) x * x)     -- [1, 4, 9, 16, 25]
filter(numbers, \(x) x > 3)  -- [4, 5]
```

---

## Pipe Operators

T provides two pipe operators with different error-handling semantics.

### Conditional Pipe (`|>`)

The standard pipe `|>` passes the left-hand value as the first argument to the right-hand function. If the left-hand value is an error, the pipeline **short-circuits** and the error is returned immediately without calling the function:

```t
5 |> \(x) x * 2           -- 10
5 |> add(3)                -- 8 (equivalent to add(5, 3))
[1, 2, 3] |> map(\(x) x * x) |> sum  -- 14

-- Short-circuits on error:
error("boom") |> double    -- Error(GenericError: "boom")
```

Pipes work across lines for readability:

```t
[1, 2, 3, 4, 5]
  |> map(\(x) x * x)
  |> sum                   -- 55
```

### Maybe-Pipe (`?|>`)

The maybe-pipe `?|>` **always** forwards the left-hand value to the right-hand function, even if it is an error. This enables explicit error recovery patterns:

```t
-- Forward normal values (same as |>):
5 ?|> double               -- 10

-- Forward errors to recovery functions:
handle = \(x) if (is_error(x)) "recovered" else x
error("boom") ?|> handle   -- "recovered"

-- Chain recovery with normal processing:
recovery = \(x) if (is_error(x)) 0 else x
increment = \(x) x + 1
error("fail") ?|> recovery |> increment  -- 1
```

The maybe-pipe also works across lines:

```t
error("fail")
  ?|> recovery
  |> increment             -- 1
```

### When to Use Each Pipe

| Operator | On Error            | Use Case                        |
|----------|---------------------|---------------------------------|
| `\|>`    | Short-circuits      | Normal data pipelines           |
| `?\|>`   | Forwards to function| Error recovery, fallback values |

---

## Conditionals

```t
result = if (5 > 3) "yes" else "no"   -- "yes"
```

Conditionals are expressions — they return values.

---

## Collections

### Lists

```t
numbers = [1, 2, 3]
length(numbers)  -- 3
head(numbers)    -- 1
tail(numbers)    -- [2, 3]
```

### Named Lists

```t
person = [name: "Alice", age: 30]
person.name  -- "Alice"
person.age   -- 30
```

### Dictionaries

```t
config = {host: "localhost", port: 8080}
config.host  -- "localhost"
config.port  -- 8080
```

---

## Missing Values (NA)

T uses explicit `NA` values with type tags. NA does **not** propagate implicitly — operations on NA produce errors:

```t
NA             -- untyped NA
na_int()       -- typed NA (Int)
na_float()     -- typed NA (Float)
na_bool()      -- typed NA (Bool)
na_string()    -- typed NA (String)

is_na(NA)      -- true
is_na(42)      -- false

-- NA does not propagate
NA + 1         -- Error(TypeError: "Operation on NA...")
```

---

## Error Handling

Errors are values, not exceptions. Failed operations return structured `Error` values:

```t
result = 1 / 0
is_error(result)     -- true
error_code(result)   -- "DivisionByZero"
error_message(result) -- "Division by zero"

-- Custom errors
err = error("something broke")
err = error("ValueError", "invalid input")
```

### Assert

```t
assert(2 + 2 == 4)                -- true
assert(false, "custom message")   -- Error(AssertionError: ...)
```

---

## DataFrames

DataFrames are T's first-class tabular data type, loaded from CSV:

```t
df = read_csv("data.csv")
nrow(df)      -- number of rows
ncol(df)      -- number of columns
colnames(df)  -- list of column names
df.age        -- column as Vector
```

### Data Manipulation

T provides six core data verbs:

```t
-- Select columns
df |> select("name", "age")

-- Filter rows
df |> filter(\(row) row.age > 25)

-- Add/transform columns
df |> mutate("age_plus_10", \(row) row.age + 10)

-- Sort rows
df |> arrange("age")        -- ascending
df |> arrange("age", "desc") -- descending

-- Group and summarize
df |> group_by("dept")
   |> summarize("count", \(g) nrow(g))
```

---

## Pipelines

Pipelines define named computation nodes with automatic dependency resolution:

```t
p = pipeline {
  data = read_csv("sales.csv")
  filtered = filter(data, \(row) row.amount > 100)
  total = filtered |> select("amount") |> \(d) sum(d.amount)
}

p.data       -- access node result
p.total      -- access computed value
```

Pipeline features:
- **Automatic dependency resolution**: Nodes can be declared in any order
- **Deterministic execution**: Same inputs always produce same outputs
- **Cycle detection**: Circular dependencies are caught and reported
- **Introspection**: `pipeline_nodes()`, `pipeline_deps()`, `pipeline_node()`
- **Re-run**: `pipeline_run()` re-executes the pipeline

---

## Standard Library

All packages are loaded automatically at startup:

| Package     | Functions                                               |
|-------------|----------------------------------------------------------|
| `core`      | `print`, `type`, `length`, `head`, `tail`, `map`, `filter`, `sum`, `seq` |
| `base`      | `assert`, `is_na`, `na`, `na_int`, `na_float`, `na_bool`, `na_string`, `error`, `is_error`, `error_code`, `error_message`, `error_context` |
| `math`      | `sqrt`, `abs`, `log`, `exp`, `pow`                      |
| `stats`     | `mean`, `sd`, `quantile`, `cor`, `lm`                   |
| `dataframe` | `read_csv`, `colnames`, `nrow`, `ncol`                  |
| `colcraft`  | `select`, `filter`, `mutate`, `arrange`, `group_by`, `summarize` |
| `pipeline`  | `pipeline_nodes`, `pipeline_deps`, `pipeline_node`, `pipeline_run` |
| `explain`   | `explain`, `intent_fields`, `intent_get`                |

### Math Functions

Pure numerical primitives that work on scalars and vectors:

```t
sqrt(4)        -- 2.0
abs(0 - 5)     -- 5
log(10)        -- 2.30258509299
exp(1)         -- 2.71828182846
pow(2, 3)      -- 8.0
```

### Stats Functions

Statistical summaries that work on lists and vectors:

```t
mean([1, 2, 3, 4, 5])             -- 3.0
sd([2, 4, 4, 4, 5, 5, 7, 9])     -- 2.1380899353
quantile([1, 2, 3, 4, 5], 0.5)   -- 3.0 (median)
cor(df.x, df.y)                   -- correlation coefficient
lm(df, "y", "x")                 -- linear regression model
```

### Introspection

```t
type(42)          -- "Int"
type(df)          -- "DataFrame"
explain(df)       -- detailed DataFrame summary
packages()        -- list of loaded packages
package_info("stats")  -- package details
```

---

## Intent Blocks

Intent blocks provide structured metadata for LLM-assisted workflows:

```t
i = intent {
  description: "Summarize user activity",
  assumes: "Data excludes inactive users"
}

intent_fields(i)            -- Dict of all fields
intent_get(i, "description") -- specific field value
```

---

## Comments

```t
-- This is a single-line comment
```

---

## Type Introspection

The `type()` function returns the type name of any value as a string:

```t
type(42)             -- "Int"
type(3.14)           -- "Float"
type(true)           -- "Bool"
type("hello")        -- "String"
type([1, 2])         -- "List"
type({x: 1})         -- "Dict"
type(NA)             -- "NA"
type(1 / 0)          -- "Error"
type(null)           -- "Null"
```

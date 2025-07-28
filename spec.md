# T Programming Language — Phase 1 Specification

> **Status**: Very early stage, conceptual + implementation-driven  
> **Purpose**: Small declarative functional language for tabular data wrangling  
> **Inspiration**: R’s tidyverse, Python’s readability, OCaml’s performance

---

## ✨ Design Goals

- **Declarative**: Focus on what to compute, not how.
- **Functional**: No mutation or side effects in user code.
- **Data-centric**: Native support for tabular data (DataFrames).
- **Minimal**: Small, learnable surface.
- **Explicit error values**: Errors propagate as first-class values.
- **Composability**: Functions, pipelines, lambdas — all composable.
- **Interactive**: REPL-driven experience.
- **Hackable**: Packages live inside the repo, easy to contribute.

---

## 🔤 Syntax Overview

- **Assignment**: `x = 3 + 4` (no `let`)
- **Identifiers**: `a`, `name`, `total_price`
- **Strings**: `"hello world"`
- **Numbers**: `42`, `3.14`
- **Booleans**: `true`, `false`
- **Lambdas**: `\(x) x + 1`
- **Function definition**: `f = function(x, y, ...) (x + y)`
- **Function call**: `mean(x)`, `select(people, name)`
- **If expressions**: `if (x > 3) "big" else "small"`
- **List literals**: `[1, 2, 3]`
- **Named list elements**: `[a: 1, b: 2]`, accessible as `x.a`
- **Dict literals**: `{name: "Alice", age: 30}`
- **Dot access**: Works on named lists and DataFrames — `x.a`, `df.name`
- **List comprehension**: `[x * x for x in [1, 2, 3]]`
- **Pipe operator**: `x |> f` or `x |> f(a, b)`
- **Dots (`...`)**: For variadic arguments and forwarding

---

## 📦 Built-in Data Types

- `Number` (int or float)
- `String`
- `Bool`
- `List` of values (optionally named)
- `Dict` (Python-style)
- `DataFrame`
- `Error` values (e.g., `"file not found"`)

---

## 📄 Example Programs

```t
-- Load a CSV file
people = read_csv("people.csv")

-- Select and filter with pipes
people
  |> select(name, age)
  |> filter(age > 30)
  |> mutate(group = if (age > 50) "senior" else "adult")

-- Define and use functions
square = \(x) x * x
map([1, 2, 3], square)

-- Using function with ...
plot = function(data, x, y, ...) (
  scatterplot(data, x = x, y = y, ...)
)

-- Function with standard notation
add = function(x, y) (x + y)

-- List comprehension
[x * x for x in [1, 2, 3]]

-- Dictionary
person = {name: "Alice", age: 30}
person.name

-- Named list
x = [a: 1, b: 2]
print(x.a)

-- DataFrame column access
df.name
```

---

## 🔧 Core Built-ins (Phase 1)

| Function           | Description                                |
|--------------------|--------------------------------------------|
| `read_csv(path)`   | Load CSV as DataFrame                      |
| `select(df, ...)`  | Select columns (NSE-like)                  |
| `filter(df, cond)` | Filter rows                                |
| `mutate(df, ...)`  | Add or transform columns                   |
| `mean(x)`          | Mean of list or DataFrame column           |
| `print(x)`         | Type-dispatched print                      |
| `map(list, f)`     | Apply function to list                     |
| `x |> f(...)`      | Pipe operator for chaining                 |

---

## 📝 Naming and Syntax Rules

- **Variable names**:
  - Can include letters, numbers, and underscores.
  - Cannot start with a number or reserved symbol.
  - Reserved symbols include: `=`, `+`, `-`, `*`, `/`, `|>`, `->`, etc.
  - To use *any* name (including spaces, numbers first, or symbols), wrap it in backticks:
    - Example: `` `hello world!` = 3 `` is legal.

- **Type annotations (optional)**:
  - Syntax: `x: Number = 3`
  - Functions: `f: (String, Number) -> Bool = function(name, age) (...)`
  - Type annotations are optional and ignored for now (parsed but not enforced).

- **Strings**:
  - Single quotes: `'hello'`
  - Double quotes: `"world"`
  - Triple quotes for multi-line strings (like Python):
    - `'''This is a\nmulti-line\nstring'''`
    - `"""Another\none"""`

```t
-- Examples
x = 3
long_name_2 = 42
`123number` = 1
`column with spaces` = 7

msg = '''This is
a long string'''
```

---

## 🧩 Packages (autoloaded at REPL startup)

- `core`: Functional primitives like `map`, `fold`, `filter`
- `stats`: Statistical functions like `mean`, `sd`
- `colcraft`: Data verbs like `select`, `filter`, `mutate` (renamed from `dplyr`)

Other packages can be added but must be explicitly loaded.

---

## 🚫 What’s Out of Scope (For Now)

- No mutation or assignments after `x = ...`
- No user-defined types yet (except via packages)
- No package registry (everything lives in repo)
- No macros or JIT (planned for later)

---

## 🧪 Error Semantics

All failed operations return a value of type `Error`, e.g.:

```t
x = read_csv("missing.csv")
print(x) -- prints: Error("file not found")
```

No exceptions — everything is a value.

---

## 🛤 Implementation Stack

- **Language**: OCaml
- **Lexer/Parser**: OCamllex + Menhir
- **Evaluation**: AST interpreter in `eval.ml`
- **REPL**: `repl.ml`
- **CSV I/O**: OCaml `csv` library
- **Packaging**: Nix flake, no external build tools

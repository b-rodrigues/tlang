# T Language Architecture

Internal design and implementation of the T programming language.

## Table of Contents

- [Overview](#overview)
- [Language Pipeline](#language-pipeline)
- [Core Components](#core-components)
- [Type System](#type-system)
- [Execution Model](#execution-model)
- [Arrow Backend](#arrow-backend)
- [Package System](#package-system)
- [Design Decisions](#design-decisions)

---

## Overview

T is a tree-walking interpreter built in OCaml. The architecture prioritizes:

1. **Simplicity**: Straightforward implementation easy to understand and modify
2. **Correctness**: Explicit semantics with no hidden behavior
3. **Reproducibility**: Deterministic execution and Nix-managed dependencies
4. **Extensibility**: Modular package system for adding functionality

**Tech Stack:**
- **Host Language**: OCaml 4.14+
- **Parser Generator**: Menhir (LR parser)
- **Lexer**: ocamllex
- **Build System**: Dune
- **Data Backend**: Apache Arrow C GLib (via FFI)
- **Package Manager**: Nix

---

## Language Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                     Source Code (.t file)                    │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ LEXER (lexer.mll)                                            │
│ • Tokenizes input (IDENT, INT, FLOAT, STRING, keywords)     │
│ • Handles operators (|>, ?|>, ~)                             │
│ • Supports multiline pipes                                   │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ PARSER (parser.mly)                                          │
│ • Builds AST from token stream                               │
│ • Operator precedence (prec/assoc directives)                │
│ • NSE for DataFrame verbs                                    │
│ • Formula syntax (y ~ x)                                     │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ AST (ast.ml)                                                 │
│ • expr type: represents all expressions                      │
│ • value type: runtime values                                 │
│ • Includes types for errors, NA, pipelines, intents          │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ EVALUATOR (eval.ml)                                          │
│ • Tree-walking interpreter                                   │
│ • Environment-based variable lookup                          │
│ • Closures capture enclosing environment                     │
│ • Conditional pipe short-circuits on errors                  │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ STANDARD LIBRARY (packages/)                                 │
│ • One file per function                                      │
│ • Mix of T (.t) and OCaml (.ml) implementations              │
│ • Auto-loaded at startup                                     │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ ARROW BACKEND (arrow/)                                       │
│ • FFI to Arrow C GLib                                        │
│ • Columnar storage for DataFrames                            │
│ • Zero-copy column access                                    │
│ • Vectorized compute kernels                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Lexer (`src/lexer.mll`)

**Purpose**: Convert source text into tokens.

**Key Features**:
- Keyword recognition (`if`, `else`, `function`, `pipeline`, etc.)
- Operators: arithmetic (`+`, `-`, `*`, `/`), comparison (`==`, `<`, `>`), logical (`and`, `or`, `not`)
- Pipe operators: `|>`, `?|>`, `~` (formula)
- Multiline support: Pipes can span multiple lines
- String literals with escape sequences
- Comments: `--` to end of line

**Example**:
```t
df |> filter($age > 30)
```

Tokens:
```
IDENT("df") PIPE IDENT("filter") LPAREN LAMBDA ...
```

### 2. Parser (`src/parser.mly`)

**Purpose**: Build abstract syntax tree (AST) from tokens.

**Grammar Highlights**:
- Expression-oriented: Everything is an expression (conditionals, blocks, etc.)
- Operator precedence: `*` / `/` bind tighter than `+` / `-`
- Pipe associativity: Left-associative (`a |> f |> g` = `(a |> f) |> g`)
- List comprehensions: `[expr for x in xs if pred]`
- Named arguments: `f(a = 1, b = 2)`

**Precedence** (low to high):
1. `|>`, `?|>` (pipes)
2. `or`
3. `and`
4. `not`
5. `==`, `!=`, `<`, `>`, `<=`, `>=`
6. `+`, `-`
7. `*`, `/`, `%`
8. Unary `-`
9. Function application

**Special Constructs**:
- **Pipelines**: `pipeline { node1 = expr1; node2 = expr2 }`
- **Intents**: `intent { field: value }`
- **Formulas**: `response ~ predictor`
- **Lambdas**: `\(x) expr` or `function(x) expr`

### 3. AST (`src/ast.ml`)

**Purpose**: Define data structures for the abstract syntax tree and runtime values.

**Key Types**:

```ocaml
(* Expression AST *)
type expr =
  | Int of int
  | Float of float
  | Bool of bool
  | String of string
  | Ident of string
  | List of expr list
  | Dict of (string * expr) list
  | Lambda of string list * expr
  | App of expr * expr list  (* Function application *)
  | BinOp of binop * expr * expr
  | UnOp of unop * expr
  | If of expr * expr * expr
  | Let of string * expr
  | Pipe of expr * expr  (* |> *)
  | MaybePipe of expr * expr  (* ?|> *)
  | Pipeline of (string * expr) list
  | Intent of (string * expr) list
  | Formula of expr * expr  (* y ~ x *)
  | ListComp of expr * string * expr * expr option
  (* ... *)

(* Runtime Values *)
type value =
  | VInt of int
  | VFloat of float
  | VBool of bool
  | VString of string
  | VList of value list
  | VDict of (string, value) Hashtbl.t
  | VFunction of string list * expr * environment
  | VDataFrame of dataframe
  | VVector of vector
  | VNA of na_type
  | VError of error_info
  | VPipeline of pipeline_data
  | VIntent of intent_data
  (* ... *)
```

**Design Notes**:
- Expressions are immutable; evaluation produces new values
- Functions capture environment as closures
- Errors and NA are first-class values, not exceptions
- DataFrames hold Arrow table handles (or fallback lists)

### 4. Evaluator (`src/eval.ml`)

**Purpose**: Execute AST nodes and produce values.

**Execution Strategy**: Tree-walking interpreter with environment-based variable lookup.

**Key Functions**:

```ocaml
(* Main evaluation function *)
val eval : environment -> expr -> value

(* Apply function to arguments *)
val apply_function : value -> value list -> value

(* Built-in operator evaluation *)
val eval_binop : binop -> value -> value -> value
val eval_unop : unop -> value -> value
```

**Environment Model**:
- Environments are hash tables: `string -> value`
- Nested scopes: Functions create child environments
- Closures: Functions capture their defining environment
- Immutability: Variables can't be reassigned (shadowing allowed)

**Pipe Evaluation**:

```ocaml
(* Conditional pipe |> *)
match eval env left with
| VError _ as err -> err  (* Short-circuit *)
| value -> apply_function (eval env right) [value]

(* Maybe-pipe ?|> *)
let value = eval env left in
apply_function (eval env right) [value]  (* Always forward *)
```

**Error Handling**:
- Errors are `VError` values, not OCaml exceptions
- Propagate through pipelines (unless caught)
- Actionable error messages with context

### 5. REPL (`src/repl.ml`)

**Purpose**: Interactive read-eval-print loop.

**Features**:
- Persistent environment across evaluations
- Pretty-printing of results
- Multiline input support
- Error recovery (don't crash on errors)
- Standard library auto-loaded at startup

**Flow**:
```
1. Read input
2. Lex & parse → AST
3. Evaluate → value
4. Pretty-print value
5. Update environment (for assignments)
6. Loop
```

---

## Type System

T is **dynamically typed** with runtime type checking.

### Value Types

| Type | OCaml Representation | Description |
|------|---------------------|-------------|
| `Int` | `VInt of int` | OCaml native int (63-bit on 64-bit systems) |
| `Float` | `VFloat of float` | OCaml float (IEEE 754 double) |
| `Bool` | `VBool of bool` | OCaml bool |
| `String` | `VString of string` | OCaml string |
| `List` | `VList of value list` | Heterogeneous lists |
| `Dict` | `VDict of (string, value) Hashtbl.t` | Mutable hash table |
| `Function` | `VFunction of params * body * env` | Closure |
| `DataFrame` | `VDataFrame of dataframe` | Arrow table or fallback |
| `Vector` | `VVector of vector` | Typed array (Int/Float/Bool/String) |
| `NA` | `VNA of na_type` | Typed missing value |
| `Error` | `VError of error_info` | Error with code, message, context |

### Type Checking

**Runtime Dispatch**: Functions check argument types at call time.

Example (addition):
```ocaml
match (left, right) with
| (VInt a, VInt b) -> VInt (a + b)
| (VFloat a, VFloat b) -> VFloat (a +. b)
| (VInt a, VFloat b) -> VFloat (float_of_int a +. b)
| (VFloat a, VInt b) -> VFloat (a +. float_of_int b)
| _ -> type_error "Cannot add {type1} and {type2}"
```

**No Static Types**: T does not have a static type system. All type errors are discovered at runtime.

---

## Execution Model

### Variable Binding

```t
x = 42
```

Evaluates the right-hand side, binds result to `x` in the current environment.

**Immutability**: Once bound, `x` cannot be reassigned. Shadowing in nested scopes is allowed:

```t
x = 1
let_block = {
  x = 2  -- Shadows outer x
  x + 10  -- 12
}
x  -- Still 1
```

### Function Application

```t
f = \(a, b) a + b
f(3, 5)  -- 8
```

1. Evaluate function expression → `VFunction(["a", "b"], body, env)`
2. Evaluate arguments → `[VInt 3, VInt 5]`
3. Create new environment extending function's captured environment
4. Bind parameters: `a → 3`, `b → 5`
5. Evaluate body in new environment → `VInt 8`

### Closures

Functions capture their defining environment:

```t
make_adder = \(n) \(x) x + n
add10 = make_adder(10)
add10(5)  -- 15
```

The inner lambda `\(x) x + n` captures the environment where `n = 10`.

### Pipeline Execution

Pipelines are DAGs of named computations:

```t
p = pipeline {
  x = 10
  y = 20
  sum = x + y
}
```

**Execution**:
1. Parse nodes → `[("x", Int 10), ("y", Int 20), ("sum", BinOp(Add, Ident "x", Ident "y"))]`
2. Topological sort (dependency order): `x`, `y`, `sum`
3. Evaluate each node, binding results: `x → 10`, `y → 20`, `sum → 30`
4. Store in `VPipeline` with results table
5. Access via `p.sum` → `30`

**Cycle Detection**: Circular dependencies produce an error:
```t
pipeline { a = b; b = a }  -- Error: Circular dependency
```

---

## Arrow Backend

T uses **Apache Arrow** for high-performance columnar data.

### Architecture

```
┌─────────────────────┐
│ T DataFrame Value   │
│ (VDataFrame)        │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐      ┌──────────────────────┐
│ Native Arrow Handle │ OR   │ Fallback (OCaml list)│
│ (arrow::Table*)     │      │ List of rows/columns │
└──────────┬──────────┘      └──────────────────────┘
           │
           ↓
┌─────────────────────────────────────────┐
│ Arrow C GLib FFI (src/arrow/)           │
│ • garrow_table_new_from_csv()           │
│ • garrow_table_get_column()             │
│ • garrow_array_get_value()              │
│ • garrow_compute_*() kernels            │
└─────────────────────────────────────────┘
           │
           ↓
┌─────────────────────────────────────────┐
│ Apache Arrow C++ (libarrow.so)          │
│ • Columnar storage                       │
│ • SIMD-accelerated compute               │
│ • Zero-copy slicing                      │
└─────────────────────────────────────────┘
```

### FFI Bindings

Located in `src/arrow/`:
- **arrow_ffi.ml**: OCaml wrappers for C functions
- **C stubs**: Interface to Arrow C GLib

**Example** (reading CSV):
```ocaml
external read_csv_native : string -> arrow_table = "caml_arrow_read_csv"
```

### Dual-Path Operations

Every DataFrame operation has two paths:

1. **Native Arrow Path** (when `native_handle` is available):
   - Use Arrow Compute kernels via FFI
   - Zero-copy operations
   - Vectorized SIMD execution

2. **Fallback Path** (when no native handle):
   - Pure OCaml implementation
   - Works on converted list-of-records
   - Slower but always available

**Example** (`filter` operation):
```ocaml
match df.native_handle with
| Some handle ->
    (* Use Arrow filter kernel via FFI *)
    arrow_compute_filter handle predicate
| None ->
    (* Fallback: OCaml list filter *)
    List.filter predicate df.rows
```

### Column Access

```t
df.age
```

Returns a `VVector`:
- If native handle: Zero-copy view into Arrow column
- If fallback: Extracted OCaml list

---

## Package System

Standard library functions are organized into packages.

### Structure

```
src/packages/
├── base/          # Errors, NA, assertions
├── core/          # Functional utilities
├── math/          # Mathematical functions
├── stats/         # Statistical functions
├── dataframe/     # CSV I/O, DataFrame ops
├── colcraft/      # Data verbs, window functions
├── pipeline/      # Pipeline introspection
└── explain/       # Debugging tools
```

**One File Per Function**: Each function lives in its own file (e.g., `mean.ml`, `filter.ml`).

### Implementation Options

1. **OCaml (`.ml`)**: Performance-critical or complex logic
   ```ocaml
   (* src/packages/stats/mean.ml *)
   let mean values na_rm =
     (* Implementation *)
   ```

2. **T (`.t`)**: Simple functions defined in T itself
   ```t
   -- src/packages/core/double.t
   double = \(x) x * 2
   ```

### Auto-Loading

All packages are loaded at REPL/script startup:

```ocaml
(* In repl.ml or main.ml *)
let initial_env = Environment.create () in
Package_loader.load_all_packages initial_env
```

Functions are registered in the global environment by name.

---

## Design Decisions

### Why Tree-Walking Interpreter?

**Pros**:
- Simple to implement and modify
- Direct AST representation
- Easy debugging
- Fast development iteration

**Cons**:
- Slower than bytecode or JIT
- No ahead-of-time optimization

**Decision**: For alpha, simplicity and correctness outweigh raw performance. Future versions may add bytecode compilation.

### Why OCaml?

**Pros**:
- Excellent parser/compiler tooling (Menhir, ocamllex)
- Strong type system for host language (prevents bugs)
- Good FFI story (C bindings for Arrow)
- Fast native compilation
- Functional paradigm matches T's design

**Cons**:
- Smaller ecosystem than Python/JavaScript
- Steeper learning curve for contributors

**Decision**: OCaml's strengths in language implementation outweigh ecosystem concerns.

### Why Apache Arrow?

**Pros**:
- Industry-standard columnar format
- Zero-copy interoperability (Parquet, R, Python, Julia)
- High-performance compute kernels
- Cross-language support

**Cons**:
- Large dependency
- C++ dependency management complexity (mitigated by Nix)
- FFI maintenance burden

**Decision**: Arrow's performance and interoperability are critical for data analysis. Nix ensures reproducible builds.

### Why Nix?

**Pros**:
- Perfect reproducibility (same inputs → same outputs)
- Declarative dependency management
- Isolated development environments
- Cross-platform consistency

**Cons**:
- Steep learning curve
- Longer initial build times
- Smaller user base than Docker

**Decision**: Reproducibility is a core value; Nix is the best tool for this goal.

### Why Explicit NA Handling?

**Pros**:
- No silent data loss
- Forces user to think about missingness
- Predictable behavior

**Cons**:
- More verbose than automatic propagation
- Requires `na_rm` parameters everywhere

**Decision**: Explicit beats implicit. R's silent NA propagation leads to subtle bugs; T forces intentionality.

### Why No Static Types?

**Pros**:
- Faster prototyping
- Simpler user experience (no type annotations)
- Easier REPL workflow

**Cons**:
- Runtime errors instead of compile-time errors
- Less safety for large codebases

**Decision**: For alpha, dynamic typing matches T's exploratory, REPL-first workflow. Static typing may be added in future versions as an optional layer.

---

## Performance Characteristics

### Asymptotic Complexity

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| Variable lookup | O(1) | Hash table |
| Function call | O(n) params | Environment copy |
| List access | O(n) | Linked list |
| DataFrame filter (native) | O(n) | Arrow kernel |
| DataFrame filter (fallback) | O(n) | OCaml iteration |
| Pipeline topological sort | O(V + E) | DAG traversal |

### Memory Model

- **Values**: Immutable, shared via references
- **DataFrames**: Arrow columnar storage (shared buffers)
- **Closures**: Capture full environment (can be large)

### Bottlenecks

1. **Function calls**: Environment copying is expensive
2. **Fallback DataFrame ops**: Pure OCaml slower than Arrow
3. **List operations**: Linked lists have poor cache locality

### Optimization Opportunities

- Bytecode compilation
- JIT for hot paths
- Persistent data structures (fewer copies)
- Lazy evaluation for pipelines
- Arrow Compute for more operations

---

## Testing Strategy

### Test Types

1. **Unit Tests**: OCaml functions in `tests/`
2. **Golden Tests**: Compare T output against R (in `tests/`)
3. **Example Tests**: Runnable examples in `examples/`
4. **Property Tests**: QuickCheck-style (future)

### Golden Test Workflow

```bash
# Run T program
dune exec src/repl.exe < tests/mean_test.t > t_output.txt

# Run equivalent R script
Rscript tests/mean_test.R > r_output.txt

# Compare
diff t_output.txt r_output.txt
```

### Testing Philosophy

- **Correctness over coverage**: Focus on semantics, not LOC coverage
- **Cross-validation**: Compare against established tools (R, Python)
- **Real-world data**: Use actual CSV files, not just synthetic data

---

## Future Architecture Directions

### Bytecode Compilation

Replace tree-walking interpreter with bytecode VM:
- Compile AST → bytecode
- Stack-based VM for execution
- Faster loops and function calls

### Type Inference

Add optional static typing:
- Hindley-Milner type inference
- Gradual typing (mix static/dynamic)
- IDE support via Language Server Protocol

### Distributed Execution

Pipeline nodes run on clusters:
- Serialize pipelines to remote workers
- Arrow Flight for zero-copy data transfer
- Fault tolerance via re-execution

### GPU Acceleration

Arrow Compute on CUDA:
- Offload aggregations to GPU
- Vectorized operations on GPU
- Requires cuDF or similar

---

**Next**: [Contributing Guide](contributing.md) | [Development Guide](development.md)

need to merge with first one 


T Programming Language — Specification

Status: Implementation-Driven Phase 1
Purpose: A pragmatic, optionally-typed functional language for data analysis.
Inspiration: R’s Tidyverse, Python’s readability, OCaml’s performance, Julia's ergonomics.

✨ Design Philosophy

Data-Centric and Opinionated: T is built specifically for data manipulation and analysis. Its core data structures and functions are designed to make common data-wrangling tasks expressive, safe, and fast.

Declarative and Functional: Focus on what to compute, not how. T avoids side effects and mutation in user code, leading to programs that are easier to reason about, parallelize, and debug.

Gradual and Pragmatic: The language should be as simple as possible, but no simpler. It provides a seamless path from simple, dynamic scripting in the REPL to building robust, statically-typed, and high-performance data pipelines.

User-Centric Indexing: The language is 1-indexed to align with the conventions of modern data analysis (R, Julia) and natural human language, reducing cognitive load and off-by-one errors in data tasks.

Hackable and Transparent Core: The language's standard library is organized into small, self-contained files within the main repository, making it easy for users to read the source, understand how functions work, and contribute.

🔤 Syntax Overview

Assignment: x = 3 + 4 (no let)

Identifiers: a, name, `total price` (backticked)

Strings: "hello world", 'hello world', '''multi-line'''

Numbers: 42, 3.14 (Default to Int64 and Float64 respectively).

Booleans: true, false

Lambdas: \(x) x + 1

Function definition: f = function(x, y) (x + y)

Function call: Supports positional mean(x) and named read_csv(file="path", skip=2) arguments.

If expressions: if (x > 3) "big" else "small"

Data Structures:

List literals: [1, "a", true]

Named list elements: [a: 1, b: 2], accessible as x.a

Dict literals: {name: "Alice", age: 30}

Tensor literals: tensor([1, 2], [3, 4])

Dot access: Works on named lists, dicts, and DataFrames — x.a, df.name.

Pipe operator: x |> f or x |> f(a, b)

📦 Built-in Data Types

T provides a rich set of data types, separating flexible general-purpose containers from high-performance ones.

General-Purpose Containers

List: An ordered, heterogeneous collection that can contain a mix of named and unnamed elements.

Dict: An unordered, key-value map with unique string keys.

String, Bool

High-Performance Containers

Tensor: A homogeneous, N-dimensional numerical array for mathematical computing. Backed by OCaml's Bigarray.

DataFrame: A 2D table with heterogeneous column types, composed of named, 1D vectors. This is the primary structure for tabular data.

Concrete Numeric Types: Int8, Int16, Int32, Int64, Float32, Float64. These are used primarily for defining schemas in Tensors and DataFrames for memory and performance optimization.

Special Values

Error: A first-class value representing a failure.

Null

🛡️ Gradual Type System

T features a powerful gradual type system where safety is introduced incrementally through annotations. This provides a seamless spectrum from dynamic scripting to robust, statically-typed programs.

Core Principle: Code without annotations is fully dynamic. Adding a type annotation (x: Int64 = ...) creates a contract that is verified at compile time by a type checker.

Type Inference: The compiler uses Hindley-Milner type inference, meaning a few key annotations can allow the checker to infer types and catch errors throughout a large portion of the code.

Annotation Syntax:

Generated t
-- Variable annotation
x: Int64 = 10

-- Function annotation
add: (Int64, Int64) -> Int64 = \(x, y) x + y

-- Generic container annotation
names: List<String> = ["Alice", "Bob"]

🔧 Core Built-ins (Phase 1)

This is an illustrative, non-exhaustive list.

Function	Description
read_csv(file, ...)	Load CSV as DataFrame. Supports options like col_names, skip, and col_types.
select(df, ...)	Select columns by name or index (1-based).
filter(df, cond)	Filter rows based on a condition.
print(x)	Type-dispatched print.
tensor(...)	Construct a high-performance numerical Tensor.

The read_csv function's col_types argument accepts a Dictionary (e.g., {id: TInt64, value: TFloat32}). Any column not specified in the dictionary will have its type inferred automatically.

🧩 Packages

The T standard library is organized into packages that are automatically loaded at REPL startup. The library is "in-house," with all packages living inside the main repository to ensure a coherent and stable ecosystem.

core: Functional primitives and file I/O (map, read_csv, etc.)

stats: Statistical functions (mean, sd, etc.)

colcraft: dplyr-style data manipulation verbs (select, filter, mutate, etc.)

🧪 Error Semantics

All failed operations return a value of type Error. No unhandled exceptions are ever exposed to the user.

Generated t
x = read_csv("missing.csv")
-- x is now the value: Error("File error: missing.csv does not exist or cannot be opened")
print(x)
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
T
IGNORE_WHEN_COPYING_END
🚀 The T Pipeline Engine (Long-Term Vision)

While T is excellent for interactive use, its core strength for production work lies in its reproducible analytical pipeline engine. T provides a set of REPL-based functions (pipeline_load, pipeline_run, pipeline_get) to manage a project defined as a Directed Acyclic Graph (DAG) of computations.

This system uses Dune as its backend execution engine, providing parallelism, persistent caching across sessions, and robust dependency tracking for free. A user can define a complex pipeline, and T will automatically run only the necessary steps to produce the final output.

Example REPL Workflow:

Generated t
-- Load the pipeline definition from a file
my_pipe = pipeline_load("project/pipeline.t")

-- Run the pipeline to compute the 'summary_stats' node, using caching
pipeline_run(my_pipe, "summary_stats")

-- Get the result and bring it into the live REPL for further work
summary = pipeline_get(my_pipe, "summary_stats")
print(summary)
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
T
IGNORE_WHEN_COPYING_END
High-Level Implementation Roadmap

This roadmap outlines the major phases of development to build T based on this specification.

Phase 1: The Core Interpreter

(Goal: A working, dynamic REPL that can execute basic data operations.)

AST Finalization: Solidify ast.ml based on the spec (Done).

Parser Update: Update lexer.mll and parser.mly to parse all specified syntax, including named arguments and tensor() literals.

Evaluator Scaffolding: Implement the core eval.ml structure. The eval_expr function must be able to visit every AST node.

Data Structure Implementation:

Implement eval logic for VList and VDict.

Write eval_helpers for constructing VDataFrame and VTensor from T values.

Built-in Package System:

Implement the src/packages directory structure.

Create a basic print function.

Implement a robust read_csv that can handle basic type guessing and create a VDataFrame with the correct vector types.

REPL Implementation: Create repl.ml with a basic read-eval-print loop that maintains an environment.

Phase 2: The Data Manipulation Engine

(Goal: Fulfill the promise of being a Tidyverse-inspired language.)

Implement colcraft Package:

select: Implement robust column selection by name (NSE) and 1-based index.

mutate: Implement adding or replacing columns. This is complex and requires careful handling of vector recycling.

filter: Implement row filtering based on a boolean condition. This requires evaluating an expression in the "context" of each row of the DataFrame.

Tensor Operations: Implement basic arithmetic (+, -, *, /) for VTensor values in eval.ml.

Statistical Primitives: Implement the stats package with functions like mean, sum, sd that can operate on DataFrame columns (vectors) and Tensors.

Phase 3: The Gradual Type System

(Goal: Introduce optional static safety.)

Parser Annotations: Update the parser to fully support parsing type annotations on function parameters, return values, and variable assignments ((Int64) -> String, List<Bool>, etc.).

Type Checker (typechecker.ml):

Implement the type environment and symbol table.

Write the core typecheck_expr function with Hindley-Milner inference.

Define the type rules for all language constructs (e.g., if expressions must have a Bool condition).

Integration: Modify the REPL and evaluation pipeline to run the type checker before the evaluator if any annotations are present. The evaluator may be able to use the type information for optimizations.

Phase 4: The Pipeline Engine

(Goal: Enable robust, reproducible, large-scale projects.)

Pipeline Parser: Create a new parser that can read a pipeline.t file and construct an in-memory graph representation of the DAG.

Dune Generator: Implement the logic that traverses the DAG and generates a dune file in a .t_cache directory, defining each node as a build rule.

Internal CLI Runner: Add the hidden t --internal-run-node command to the main executable, which knows how to load cached dependencies and execute a single node's expression.

REPL API: Implement the user-facing pipeline functions (pipeline_load, pipeline_run, etc.) as wrappers that call the Dune backend. This involves shelling out to run dune build and using Marshal to load results.

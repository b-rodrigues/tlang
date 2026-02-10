# T Alpha Release — v0.1

> **Release Date**: February 2026  
> **Status**: Alpha — syntax and semantics frozen

---

## What is T?

T is a functional programming language designed for declarative, tabular data manipulation. It combines pipeline-driven workflows with explicit semantics, making data analysis clear, reproducible, and composable.

---

## Alpha Scope

This alpha release validates T's core design ideas:

- **Pipelines**: DAG-based execution with named nodes, dependency resolution, and caching
- **Tabular Data**: First-class DataFrames with CSV reading/writing and column access
- **Data Manipulation**: Six core verbs — `select`, `filter`, `mutate`, `arrange`, `group_by`, `summarize`
- **Explicit Semantics**: Structured errors with actionable messages (name suggestions, type hints), typed NA values, no implicit propagation
- **Standard Library**: Math, statistics, and data manipulation packages loaded by default
- **LLM-Friendly**: Intent blocks and `explain()` for machine-readable metadata
- **Interactive**: REPL with multi-line input and pretty-printing

---

## Frozen Syntax

The following syntax is frozen for the alpha release and will not change:

### Literals
```t
42              -- Int
3.14            -- Float
true / false    -- Bool
"hello"         -- String
NA              -- Missing value
null            -- Null
```

### Operators
```t
+ - * /         -- Arithmetic
== != < > <= >= -- Comparison
and or not      -- Logical
|>              -- Conditional pipe (short-circuits on error)
?|>             -- Unconditional pipe (forwards errors to function)
```

### Data Structures
```t
[1, 2, 3]                  -- List
[name: "Alice", age: 30]   -- Named list
{key: value}               -- Dict
```

### Functions
```t
\(x) x + 1                 -- Lambda (preferred)
function(x) x + 1          -- Function keyword
f(x, y)                    -- Function call
```

### Control Flow
```t
if (cond) expr else expr    -- Conditional expression
```

### Pipelines
```t
pipeline {                  -- Pipeline definition
  name = expression
}
```

### Intent Blocks
```t
intent {                    -- LLM metadata
  key: "value"
}
```

### Comments
```t
-- This is a comment
```

---

## Standard Library

| Package     | Functions                                                |
|-------------|----------------------------------------------------------|
| `core`      | `print`, `type`, `length`, `head`, `tail`, `map`, `filter`, `sum`, `seq`, `pretty_print` |
| `base`      | `assert`, `is_na`, `na`, `na_int`, `na_float`, `na_bool`, `na_string`, `error`, `is_error`, `error_code`, `error_message`, `error_context` |
| `math`      | `sqrt`, `abs`, `log`, `exp`, `pow`                       |
| `stats`     | `mean`, `sd`, `quantile`, `cor`, `lm`                    |
| `dataframe` | `read_csv`, `write_csv`, `colnames`, `nrow`, `ncol`      |
| `colcraft`  | `select`, `filter`, `mutate`, `arrange`, `group_by`, `summarize` |
| `pipeline`  | `pipeline_nodes`, `pipeline_deps`, `pipeline_node`, `pipeline_run` |
| `explain`   | `explain`, `explain_json`, `intent_fields`, `intent_get` |

---

## Known Limitations

- **No persistent package registry**: All packages are in the main repository
- **No pattern matching**: `match` expressions are planned for beta
- **No lenses**: Immutable update helpers are planned for beta
- **No list comprehensions**: Syntax is reserved but not yet implemented
- **Performance**: Tree-walking interpreter; no optimization passes
- **No GPU/distributed execution**: Single-threaded execution only
- **CSV only**: No Parquet, JSON, or database connectors yet

---

## Getting Started

### Quick Start with Nix

```bash
# Try T directly from GitHub
nix run github:b-rodrigues/tlang

# Run a script
nix run github:b-rodrigues/tlang -- run examples/ci_test.t
```

### Build from Source

```bash
git clone https://github.com/b-rodrigues/tlang.git
cd tlang
nix develop
dune build
dune exec src/repl.exe
```

### Run Tests

```bash
dune test
```

---

## Documentation

- [Language Overview](docs/language_overview.md) — Complete language reference
- [Pipeline Tutorial](docs/pipeline_tutorial.md) — Step-by-step pipeline guide
- [Data Manipulation Examples](docs/data_manipulation_examples.md) — Practical data wrangling
- [Language Specification](spec.md) — Full design specification

---

## Examples

- [`examples/ci_test.t`](examples/ci_test.t) — Comprehensive integration test
- [`examples/data_analysis.t`](examples/data_analysis.t) — End-to-end data analysis
- [`examples/pipeline_example.t`](examples/pipeline_example.t) — Pipeline features
- [`examples/statistics_example.t`](examples/statistics_example.t) — Math and statistics
- [`examples/error_recovery.t`](examples/error_recovery.t) — Error recovery with maybe-pipe (`?|>`)

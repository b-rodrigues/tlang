# T — A Language for Tabular Data and Human–LLM Collaboration

**T** is an experimental programming language for declarative, functional manipulation of tabular data. Inspired by R’s tidyverse and OCaml’s semantic rigor, T is designed to make data analysis **explicit, inspectable, and pipeline-oriented**.

Unlike traditional scripting languages, T is built from the ground up to support **human–LLM collaborative programming**, where humans specify intent and constraints, and language tools (including LLMs) generate localized, mechanical code.

**Status:** Alpha 0.51. Core syntax and functional semantics are stable.

---

## Documentation

### Getting Started
- [Getting Started Guide](getting-started.html) — first steps with T
- [Installation Guide](installation.html) — detailed setup with Nix
- [Language Overview](language_overview.html) — types, syntax, functions, and standard library
- [Type System](type-system.html) — detailed guide to T's type hierarchy and semantics
- [Numerical Arrays](arrays.html) — tutorial on N-dimensional arrays and linear algebra
- [Editor Support](editors.html) — setup guide for Vim, Emacs, and VS Code

### User Guides
- [API Reference](api-reference.html) — complete function reference by package
- [Data Manipulation Examples](data_manipulation_examples.html) — practical examples with core data verbs
- [Factors & Categorical Data](factors.html) — factor creation, level ordering, and `fct_*` helpers
- [String Manipulation](string_manipulation.html) — naming rules, examples, and exceptions for text helpers
- [Pipeline Tutorial](pipeline_tutorial.html) — step-by-step guide to T's pipeline model
- [Literate Programming with Quarto](literate-programming-quarto.html) — rendering reports from pipelines
- [Statistical Models](models.html) — linear regression, GLMs, and broom-style output
- [Handling Dates](handling_dates.html) — parsing, extraction, and date arithmetic
- [Error Handling Guide](error-handling.html) — error patterns and recovery strategies
- [Comprehensive Examples](examples.html) — real-world analysis patterns

### Advanced Topics
- [Reproducibility Guide](reproducibility.html) — Nix integration and reproducible workflows
- [LLM Collaboration](llm-collaboration.html) — intent blocks and AI-assisted development
- [Quotation & Metaprogramming](quotation.html) — capturing and generating code
- [Statistical Formulas](formulas.html) — formula syntax for modeling
- [Performance](performance.html) — Arrow backend and optimization
- [Performance Analysis](performance_analysis.html) — in-depth analysis of T's performance metrics

### Developer Resources
- [Architecture](architecture.html) — language design and implementation
- [Contributing Guide](contributing.html) — how to contribute to T
- [Development Guide](development.html) — building, testing, and debugging
- [Project Development](project_development.html) — managing T projects and workspaces
- [Package Development Guide](package_development.html) — creating and publishing T packages

### Reference & Support
- [Function Reference](reference/index.html) — exhaustive per-function guide
- [FAQ](faq.html) — frequently asked questions
- [Troubleshooting](troubleshooting.html) — common issues and solutions
- [Changelog](changelog.html) — history of changes and releases

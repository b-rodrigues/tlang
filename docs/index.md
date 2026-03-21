# T — The Orchestration Engine for Polyglot Data Science

**T** is an experimental orchestration engine designed for declarative, reproducible pipelines. It provides a functional Domain-Specific Language (DSL) that coordinates R, Python, Julia, and Shell nodes within a Nix-managed infrastructure.

Unlike traditional scripting languages, T is built to be a **specifications-ready engine**, making data analysis **explicit, inspectable, and pipeline-oriented**. This unique architecture ensures that humans and LLMs can collaborate on defining high-level intent while T handles the low-level orchestration and environmental consistency.

**Status:** Version 0.52.1 "Sangoku", latest stabilization release.

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
- [T Pipeline Demos](demos.html) — interactive reports for T demo projects

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

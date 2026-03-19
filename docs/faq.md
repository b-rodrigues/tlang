# Frequently Asked Questions (FAQ)

Welcome to the **T Orchestration Engine** FAQ. This guide covers the philosophy, technical architecture, and practical usage of T.

---

## General Questions

### What makes T different?
T isn't just another data analysis language; it's a **reproducibility-first** engine. While R and Python rely on external tools for environment management, T integrates **Nix** at its core. Every workflow is a statically defined directed acyclic graph (DAG) called a **Pipeline**, ensuring that your analysis is as stable as the hardware it runs on.

### Who should use T?
- **Scientific Researchers**: Who need ironclad, auditable proof of how results were derived.
- **Data Engineering Teams**: Looking for a polyglot orchestration layer that passes data between R and Python without serialization overhead.
- **LLM-First Developers**: T's functional, immutable, and pipeline-centric design is optimized for high-fidelity code generation by AI.

### Is T production-ready?
T is currently in **Beta (v0.51.0)**. While it is an experimental project, it is already fully capable of performing end-to-end data processing. You can use T's native **data manipulation verbs** and **Quarto integration** to build reports without ever leaving the language. For more complex statistical modeling or advanced visualization, you can easily pull in R or Python nodes.

---

## The Technical Core

### How does the Polyglot Architecture work?
T uses **Apache Arrow** as its core data exchange format. When you pass a DataFrame between a T node and an **R (`rn()`)**, **Python (`pyn()`)**, or **Shell (`shn()`)** node, T handles the interchange using highly efficient Arrow files. 
- **Hermeticity**: Because T runs every node in a hermetic Nix sandbox, data cannot be shared directly in memory.
- **Serialization**: Dataframes are serialized to Arrow IPC files on disk. This is still significantly faster and more robust than traditional CSV/JSON interchange.
- **Fidelity**: All level metadata for factors and nested list-columns is preserved through the serialization process.
- **Model Interchange**: Machine learning models are passed between languages using **PMML**.

### What is NSE and why the `$` prefix?
T uses **Non-Standard Evaluation (NSE)** to make data manipulation concise. The `$` prefix (e.g., `filter($age > 30)`) identifies column names or variables in the data context, similar to `rlang` in R but built directly into the language syntax for clarity.

### How are missing values (NA) handled?
T takes a strict approach to safety. Unlike other languages where `NA` might propagate silently, T requires explicit handling. 
- Aggregation functions will **throw an error** if they encounter an `NA` unless you pass `na_rm = true`.
- Native types like `na_int()`, `na_float()`, and `na_string()` ensure type-safe missingness.

### Does T have loops or mutable state?
**No.** T is a pure functional language. 
- Instead of `for` or `while` loops, use `map()`, `filter()`, or **recursion**.
- Variables are immutable. This prevents the "spaghetti state" common in long data scripts.

---

## Pipelines & Reproducibility

### Why are Pipelines mandatory?
For non-interactive work, T enforces a `pipeline` block. This ensures that every step of your analysis is declared as a node in a graph. This architecture:
1. Prevents order-of-execution bugs (scripts that only work if run in a specific sequence).
2. Enables **automatic parallelization** of independent nodes.
3. Allows for advanced graph operations like `swap()`, `rewire()`, and `upstream_of()`.

### Do I need to know Nix?
Not for basic work. Running `nix develop` sets up your entire environment. However, T's power comes from Nix—it handles your OCaml, R, Python, and system dependencies in a single, pinned `flake.lock`.

### What operating systems are supported?
- **Linux**: Full **native support** on all modern distributions.
- **macOS**: Full **native support** via the Nix installer (Intel and Apple Silicon).
- **Windows**: Fully supported via **WSL2** (Windows Subsystem for Linux).
- **Docker**: T can build its own Docker images using Nix, making deployment to the cloud seamless.

---

## Data Manipulation & Features

### What libraries are included?
The T standard library includes:
- **`colcraft`**: A powerful suite of verbs (`mutate`, `summarize`, `pivot_longer`) following `tidyverse` semantics.
- **`chrono`**: Precise date and time manipulation with calendar-aware rounding.
- **`factors`**: Native Arrow-backed categorical data handling.

### How do I program with column names?
If you're building a reusable function that takes a column name as an argument, T provides first-class support for **Metaprogramming**:
- Use `enquo(col)` to capture the argument.
- Use `!!` (unquote) to inject it into a verb.
- Use `!!name := value` for dynamic column naming.

Example:
```t
my_avg = \(df, col, name)
  df |> summarize(!!name := mean(!!col))
```

### How do I visualize data?
For simple reports, you can use T's built-in **`colcraft`** verbs to summarize data and output it via **Quarto**. While T does not currently have its own native plotting library, its high-fidelity interop with R and Python makes it trivial to define a specialized node for more complex charts using `ggplot2`, `matplotlib`, or `seaborn`.

### Can T handle large datasets?
**Yes.** T's native Arrow backend allows it to perform `select`, `filter`, and `sort` operations directly on Arrow tables in memory. 
- **Optimized Compute**: T's built-in compute engine handles millions of rows by interacting directly with Arrow memory buffers.
- **Orchestration**: For massive datasets, you can leverage T to orchestrate R's `dtplyr` or Python's `polars` nodes. The results are passed back via Arrow serialization, maintaining high fidelity.

---

## Developer Experience

### Is there an LSP or VS Code support?
Yes! The T Language Server (`t-lsp`) provides:
- **Autocompletion**: For functions, variables, and even **DataFrame column names**.
- **Hover Docs**: View docstrings directly in your editor.
- **Diagnostics**: Real-time syntax and type error reporting.

### What about the REPL?
The T REPL is designed for productivity:
- **Ghost Hints**: Inline suggestions based on your command history.
- **Signal Safety**: Hit `Ctrl+C` to cancel a long-running calculation without crashing the session.
- **Multi-line Detection**: Automatic detection of nested blocks for easy copy-pasting.

### Can I write Literate Programming reports?
Absolutely. T integrates with **Quarto** through a native extension. You can write `.qmd` files where code chunks are written in **pure T**, allowing you to summarize data and generate professional reports without ever needing R or Python. For advanced charting or low-level file processing, you can mix T chunks with R, Python, or **Shell** (using the `shn()` function) in the same document.

---

## Community & Contributing

### How can I help?
T is an open-source project. You can contribute by:
- Porting R/Python utility functions to native T.
- Improving the `t-lsp` implementation.
- Reporting bugs or suggesting features on [GitHub](https://github.com/b-rodrigues/tlang/issues).

### What's next on the roadmap?
The developer (Bruno Rodrigues) works on T based on community interest and experimental whims. High-priority items include **Julia integration** and expanding the native Arrow compute engine.

---

> [!TIP]
> **Need help?** Check out the [Getting Started](getting-started.md) guide or join the [GitHub Discussions](https://github.com/b-rodrigues/tlang/discussions).

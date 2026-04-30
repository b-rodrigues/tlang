# Agent Guide: T Package (Reusable Library)

This file provides critical context for AI agents (and human collaborators) working on this **T package**. Following these rules ensures the library is portable, well-documented, and safe for others to import.

> [!IMPORTANT]
> **Mandatory Language Reference**: Before performing any tasks, you MUST read the **`T-LANGUAGE-REFERENCE.md`** file located in the project root. It contains essential syntax, standard library signatures, and API conventions specific to this version of the T language.

---

## 1. Package Philosophy

- **Modularity**: Every function should do one thing well.
- **Portability**: Never assume project-specific file paths (e.g., `data/`). All inputs should be passed as arguments.
- **Purity**: Prefer pure functions. Avoid side effects like `print()` or writing to disk unless that is the primary purpose of the function.
- **Data-First**: The data argument MUST be the first positional parameter to ensure compatibility with the pipe operator (`|>`).

---

## 2. API Design and Visibility

- **Exports**: By default, all functions in `src/` are exported. 
- **Private Functions**: Use the `@private` tag in T-Doc comments to hide internal helper functions from the package namespace.
- **Consistency**: Follow `tidyverse` naming conventions (snake_case) and argument ordering (required first, then optional named arguments).
- **Error Handling**: Never use placeholders. If a function encounters invalid input, return a descriptive `VError` using `error("PackageName", "message")`.

---

## 3. Documentation (T-Doc)

Every public function MUST have a T-Doc block using the `--#` syntax.
```t
--# Short description of the function
--#
--# Longer explanation of behavior and edge cases.
--#
--# @name function_name
--# @param data :: DataFrame The input data.
--# @param scale :: Float = 1.0 A scaling factor.
--# @return :: DataFrame The transformed data.
--# @export
```
Run `t doc --generate` to verify that documentation builds correctly.

---

## 4. Testing Requirements

- **Location**: All tests belong in the `tests/` directory.
- **Coverage**: Every exported function must have at least one unit test.
- **Test Command**: Run `t test` to execute the suite.
- **Isolation**: Tests should not depend on external state or internet access.

---

## 5. Dependency Management

- **Manifest**: Dependencies are declared in `DESCRIPTION.toml` (or `tproject.toml` for modern packages).
- **Versioning**: Be specific about version requirements for imported packages.
- **Update**: Run `t update` after adding a dependency to refresh the development environment.

---

## 6. Standard Package Structure

```text
.
├── DESCRIPTION.toml    # Package metadata and dependencies
├── src/                # T source files (.t)
├── tests/              # Unit tests
├── docs/               # Vignettes and extended documentation
└── README.md           # Package overview and usage examples
```

---

## 7. Common Commands for Agents

| Task | Command |
| :--- | :--- |
| **Run Tests** | `t test` |
| **Build Docs** | `t doc --parse --generate` |
| **Check Metadata** | `t doctor` |
| **Sync Environment** | `t update` |
| **Check Exports** | `t packages --info <current-package>` |

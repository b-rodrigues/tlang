# Manual Validation Checklist: Version 0.52.2

This document outlines the step-by-step manual validation procedures required to verify the stability, safety safeguards, and observability features of the **v0.52.2** release.

---

## 1. Reserved Keyword & Built-in Protection 🛡️

### REPL Verification
Launch the REPL (`t repl` or `dune exec src/repl.exe`) and verify that core keywords and built-in functions are strictly protected:

- [ ] **First-Time Assignment (`=`) on `print`**:
  ```t
  print = 42
  ```
  *Expected Output:* `Error(NameError: Cannot overwrite print: it's a reserved keyword!)`
  
- [ ] **Reassignment (`:=`) on `print`**:
  ```t
  print := 42
  ```
  *Expected Output:* `Error(NameError: Cannot overwrite print: it's a reserved keyword!)`

- [ ] **First-Time Assignment (`=`) on `build_log`**:
  ```t
  build_log = 42
  ```
  *Expected Output:* `Error(NameError: Cannot overwrite build_log: it's a reserved keyword!)`

- [ ] **Reassignment (`:=`) on `build_log`**:
  ```t
  build_log := 42
  ```
  *Expected Output:* `Error(NameError: Cannot overwrite build_log: it's a reserved keyword!)`

- [ ] **Dynamic Evaluation Block Protection**:
  Verify that dynamic safety holds within `eval()` blocks:
  ```t
  eval(to_expr({ print = 42 }))
  ```
  *Expected Output:* `Error(NameError: Cannot overwrite print: it's a reserved keyword!)`

- [ ] **Standard Variable Reassignment Coherence**:
  Verify that regular user-defined variables are still fully reassignable:
  ```t
  x = 10
  x := 20
  print(x)
  ```
  *Expected Output:* `20` (No safety warnings/errors)

---

## 2. Package Scoping & Namespaces 📦

Verify that package-scoped definitions do not trigger reserved keyword name conflicts with standard library built-ins (e.g. custom `mean` functions):

- [ ] **Local Package Import Isolation**:
  * Create a temporary package or import structure where a function `mean` is defined inside a local package environment.
  * Import and load the package.
  * Verify that loading does *not* raise any NameError during package initialization and resolves safely under the package prefix/scoping.

---

## 3. Structured Build Logs & Observability 📊

Start a new T session, build a simple pipeline, and inspect the build log values:

- [ ] **Basic Pipeline Build & Record Retrieval**:
  ```t
  p = pipeline { x = 10; y = x + 5 }
  build_pipeline(p)
  log = build_log(p)
  print(log.duration)
  print(log.failed_nodes)
  ```
  *Expected Output:* `log` is a valid `VBuildLog` record; duration is a float representing build time; `failed_nodes` is `[]`.

- [ ] **Build Log Tabulation**:
  ```t
  df = build_log_to_frame(log)
  print(df)
  ```
  *Expected Output:* An Arrow-backed DataFrame with 2 rows (one for `x`, one for `y`) containing column headers `name`, `status`, and `duration`.

- [ ] **Unified Build Log Saving on Failed Build**:
  Build a pipeline containing a hard error in a node (e.g. `pyn` with a Python runtime exception) and verify that the build log is written to `_pipeline/` even when the build fails, permitting full diagnostics inspection:
  ```t
  p = pipeline { x = pyn(script = "raise ValueError('Test Failure')") }
  build_pipeline(p) # Or t_make()
  log = build_log(p)
  print(log.failed_nodes)
  ```
  *Expected Output:* `log` is a valid `VBuildLog` record; `failed_nodes` is `["x"]`.

---

## 4. Error Composition Primitives 🧩

Build a failing pipeline resiliently, then collect and chain the diagnostic errors:

- [ ] **Collect Exceptions and Warnings from DAG (`collect_exceptions`)**:
  ```t
  p = pipeline { a = 1 / 0; b = a + 5 }
  build_pipeline(p)
  exceptions = collect_exceptions(p)
  pretty_print(exceptions)
  ```
  *Expected Output:* A DataFrame with columns `node`, `status`, `code`, and `message` detailing the failures of both `a` and `b`.

- [ ] **Explicit Error Chaining**:
  ```t
  err_low = error("ValueError", "Low-level connection refused")
  err_high = error("PipelineError", "Failed to resolve database node")
  chained = error_chain(err_high, err_low)
  print(explain(chained))
  ```
  *Expected Output:* A structured traceback displaying the causal link showing that `err_high` was caused by `err_low`.

---

## 5. Shell Nodes & Stdout Capture 🐚

- [ ] **Shell node convenience wrapper and stdout capture (`shn`)**:
  ```t
  p = pipeline {
    echo_node = shn(command = "echo", args = ["manual validation success"], capture = "stdout")
  }
  build_pipeline(p)
  read_node("echo_node")
  ```
  *Expected Output:* `"manual validation success\n"`

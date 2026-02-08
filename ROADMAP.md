# T Language Roadmap

> Beyond the Alpha Release

---

## Completed: Alpha (v0.1)

The alpha release validates T's core design:

- [x] Language core: arithmetic, functions, closures, pipes
- [x] Explicit semantics: structured errors, typed NA, no implicit propagation
- [x] DataFrames: CSV loading, schema introspection, column access
- [x] Data verbs: select, filter, mutate, arrange, group_by, summarize
- [x] Pipelines: DAG execution, dependency resolution, caching
- [x] Math/Stats: sqrt, abs, log, exp, pow, mean, sd, quantile, cor, lm
- [x] Intent blocks: LLM-friendly metadata and explain()
- [x] REPL & CLI: interactive development, script execution
- [x] Documentation: language overview, tutorials, examples
- [x] Test coverage: unit tests, golden tests, integration tests

---

## Next: Beta (v0.2)

### Language Features

- [ ] **Pattern matching**: `match` expression for deconstructing values
  ```t
  match result {
    Error(e) -> handle_error(e)
    NA -> default_value
    x -> process(x)
  }
  ```

- [ ] **List comprehensions**: Currently reserved syntax, to be implemented
  ```t
  [x * x for x in numbers if x > 2]
  ```

- [ ] **Lenses**: Composable immutable update helpers
  ```t
  updated = set(config, "port", 9090)
  ```

- [ ] **String interpolation**: Cleaner string formatting
  ```t
  "Hello, {name}! You are {age} years old."
  ```

### Data Features

- [ ] **Multiple file formats**: Parquet, JSON, TSV support
- [ ] **Write operations**: `write_csv()`, `write_parquet()`
- [ ] **Join operations**: `left_join()`, `inner_join()`, `full_join()`
- [ ] **Pivot operations**: `pivot_wider()`, `pivot_longer()`
- [ ] **Window functions**: `lag()`, `lead()`, `row_number()`

### Statistics

- [ ] **Distribution functions**: `rnorm()`, `rbinom()`, `dnorm()`
- [ ] **Hypothesis testing**: `t_test()`, `chi_squared()`
- [ ] **Multiple regression**: `lm()` with multiple predictors
- [ ] **Model summary**: `summary(model)` with structured output

### Tooling

- [ ] **Syntax highlighting**: VS Code extension, tree-sitter grammar
- [ ] **Language server**: Basic LSP for editor integration
- [ ] **Debugger**: Step-through pipeline execution
- [ ] **Formatter**: `t fmt` for consistent code style

---

## Future: v1.0

### Performance

- [ ] **Bytecode compiler**: Move from tree-walking to bytecode VM
- [ ] **Arrow backend**: Real Apache Arrow integration for DataFrames
- [ ] **Lazy evaluation**: Compute on demand for large datasets
- [ ] **Parallel execution**: Multi-threaded pipeline nodes

### Ecosystem

- [ ] **Package system**: Versioned package registry
- [ ] **Documentation generator**: Auto-generate docs from code
- [ ] **Notebook interface**: Jupyter-like interactive environment
- [ ] **Database connectors**: PostgreSQL, SQLite, DuckDB

### Language

- [ ] **Type system**: Optional static types with inference
- [ ] **Modules**: Namespace management and imports
- [ ] **Transient mutation**: Locally-scoped mutation for performance
- [ ] **Custom types**: User-defined algebraic data types

---

## Design Principles (Unchanged)

These principles guide all future development:

1. **Explicit over implicit**: No hidden behavior, no silent coercion
2. **Data-first**: Every feature is evaluated by how it helps data workflows
3. **Composable**: Small functions that combine cleanly via pipes
4. **Reproducible**: Same inputs always produce same outputs
5. **Inspectable**: Every value can be explained and introspected
6. **Minimal**: Add features only when they provide clear value

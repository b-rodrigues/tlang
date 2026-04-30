# T Language Reference (LLM Context)

This file is a distilled reference for the **T programming language**. It is intended to provide immediate context for AI agents working in this environment.

---

## 1. Core Syntax & Semantics

- **Assignment**: `x = 10` (Immutability is default).
- **Functions**: `add = \(a, b) a + b`.
- **Pipes**:
  - `x |> f(...)`: Passes `x` as the first argument. Stops on `Error`.
  - `x ?|> f(...)`: Forwards errors; used for recovery/inspection.
- **NSE (Non-Standard Evaluation)**: Use `$col` for column references in data verbs.
- **Blocks**: `[1, 2]` (List), `[k: v]` (Dict), `{ ... }` (Code block).
- **Control**: `ifelse(cond, yes, no)`, `case_when(...)`, `match(x) { ... }`.

---

## 2. Standard Packages (Auto-loaded)

### `colcraft` (Data Manipulation)
`select(df, ...)`, `filter(df, expr)`, `mutate(df, ...)`, `arrange(df, ...)`, `group_by(df, ...)`, `summarize(df, ...)`, `count(df, ...)`, `left_join(x, y, by)`, `inner_join(x, y, by)`.

### `stats` & `math` (Analysis)
`mean(x, na_rm=false)`, `median(x)`, `sd(x)`, `var(x)`, `quantile(x, probs)`, `cor(x, y)`, `lm(data, formula)`, `predict(model, data)`, `abs(x)`, `sqrt(x)`, `log(x)`, `round(x, digits)`.

### `chrono` (Dates & Times)
`ymd(s)`, `mdy(s)`, `today()`, `now()`, `year(x)`, `month(x)`, `day(x)`, `as_date(x)`, `format_date(x, format)`.

### `strcraft` (Strings)
`str_nchar(s)`, `str_substring(s, start, end)`, `str_replace(s, pat, repl)`, `to_lower(s)`, `to_upper(s)`, `str_join(xs, sep)`.

### `base` & `core` (Foundation)
`print(...)`, `type(x)`, `length(x)`, `is_na(x)`, `is_error(x)`, `error(msg)`, `serialize(val, path)`, `deserialize(path)`.

---

## 3. Pipelines & Interoperability

- **Node Creation**: 
  - `node(command = ..., runtime = T)`
  - `rn(script = ..., serializer = "arrow")` (R node)
  - `pyn(script = ..., serializer = "arrow")` (Python node)
  - `shn(command = ...)` (Shell node)
- **Artifacts**:
  - `read_node("name")`: Access output of an upstream node.
  - `pipeline_copy(p, node="name", to="path")`: Export artifacts.
- **Sandboxing**: Every node runs in a isolated Nix environment declared in the project manifest.

---

## 4. Key Principles

1. **Data-First**: Always `function(data, ...)`.
2. **No Null**: Use `NA` for missingness and `VError` for failures.
3. **Reproducibility**: Favor pipelines over monolithic scripts.
4. **Explicitness**: No implicit side effects; all dependencies must be declared.

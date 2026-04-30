# T Language Reference (Medium - LLM Context)

This file is a comprehensive reference for the **T programming language**. It covers core syntax, principles, and an exhaustive index of standard library functions.

---

## 1. Core Syntax & Semantics

- **Assignment**: `x = 10` (Immutability is default).
- **Functions**: `add = \(a, b) a + b`.
- **Pipes**:
  - `x |> f(...)`: Passes `x` as the first argument. Stops on `Error`.
  - `x ?|> f(...)`: Forwards errors; used for recovery/inspection.
- **NSE (Non-Standard Evaluation)**: Use `$col` for column references in data verbs (e.g., `filter($age > 18)`).
- **Blocks**: `[1, 2]` (List), `[k: v]` (Dict), `{ ... }` (Code block).
- **Control**: `ifelse(cond, yes, no)`, `case_when(...)`, `match(x) { ... }`.
- **Imports**: `import pkg`, `import pkg[name1, name2]`, `import pkg[alias = original]`.

---

## 2. Standard Package Index

### `base` (Core Values & Errors)
`assert(cond, msg)`, `is_na(x)`, `na()`, `na_int()`, `na_float()`, `na_bool()`, `na_string()`, `error(msg)`, `error(code, msg)`, `error_code(err)`, `error_message(err)`, `error_context(err)`, `serialize(val, path)`, `deserialize(path)`, `t_write_json(val, path)`, `t_read_json(path)`.

### `core` (Introspection & Collections)
`print(...)`, `cat(...)`, `pretty_print(x)`, `type(x)`, `args(fn)`, `help(name)`, `apropos(q)`, `packages()`, `package_info(name)`, `is_error(x)`, `length(x)`, `head(x, n)`, `tail(x, n)`, `get(x, key)`, `map(xs, fn)`, `sum(xs, na_rm)`, `seq(start, end, by)`, `to_integer(x)`, `to_float(x)`, `to_numeric(x)`, `run(cmd)`, `exit(code)`, `getwd()`, `file_exists(path)`, `dir_exists(path)`, `read_file(path)`, `list_files(path)`, `env(name)`, `path_join(...)`, `path_basename(path)`, `path_dirname(path)`, `path_ext(path)`, `path_stem(path)`, `path_abs(path)`.

### `dataframe` (I/O & Arrow)
`dataframe(...)`, `read_csv(path, ...)`, `read_parquet(path)`, `read_arrow(path)`, `write_csv(df, path)`, `write_arrow(df, path)`, `colnames(df)`, `nrow(df)`, `ncol(df)`, `glimpse(df)`, `pull(df, col)`, `to_array(df, cols)`, `clean_colnames(df)`.

### `colcraft` (Tabular Verbs)
`select(df, ...)`, `filter(df, expr)`, `mutate(df, ...)`, `arrange(df, ..., direction)`, `group_by(df, ...)`, `ungroup(df)`, `summarize(df, ...)`, `rename(df, ...)`, `relocate(df, ...)`, `distinct(df, ...)`, `count(df, ...)`, `slice(df, indices)`, `slice_min(df, ...)`, `slice_max(df, ...)`, `pivot_longer(df, ...)`, `pivot_wider(df, ...)`, `complete(df, ...)`, `expand(df, ...)`, `nest(df, ...)`, `unnest(df, col)`, `separate(df, ...)`, `unite(df, ...)`, `left_join(x, y, by)`, `inner_join(x, y, by)`, `full_join(x, y, by)`, `semi_join(x, y, by)`, `anti_join(x, y, by)`, `bind_rows(...)`, `bind_cols(...)`.
- **Selection Helpers**: `starts_with()`, `ends_with()`, `contains()`, `everything()`, `where()`, `matches()`, `all_of()`, `any_of()`.
- **Factors**: `factor(x, levels)`, `as_factor(x)`, `fct_reorder()`, `fct_relevel()`, `fct_lump_n()`.

### `chrono` (Dates & Times)
`ymd(x)`, `mdy(x)`, `dmy(x)`, `ymd_hms(x)`, `today()`, `now()`, `make_date()`, `make_datetime()`, `year(x)`, `month(x)`, `day(x)`, `wday(x)`, `week(x)`, `quarter(x)`, `tz(x)`, `as_date(x)`, `as_datetime(x)`, `format_date(x)`, `floor_date(x, unit)`, `with_tz(x, tz)`, `force_tz(x, tz)`.

### `math` (Scalar & Arrays)
`abs(x)`, `sqrt(x)`, `log(x)`, `exp(x)`, `pow(b, e)`, `floor(x)`, `ceiling(x)`, `round(x, digits)`, `sin(x)`, `cos(x)`, `tan(x)`, `ndarray(data, shape)`, `matmul(a, b)`, `inv(x)`, `transpose(x)`.

### `stats` (Statistics & Models)
`mean(x, na_rm)`, `median(x)`, `min(x)`, `max(x)`, `range(x)`, `var(x)`, `sd(x)`, `quantile(x, probs)`, `cor(x, y)`, `cov(x, y)`, `pnorm(x, mean, sd)`, `lm(data, formula)`, `predict(model, data)`, `summary(model)`, `fit_stats(model)`, `coef(model)`, `residuals(model)`, `augment(data, model)`, `t_read_pmml(path)`, `t_read_onnx(path)`.

### `pipeline` (Execution & DAG)
`node(...)`, `rn(...)`, `pyn(...)`, `shn(...)`, `build_pipeline(p)`, `pipeline_run(p)`, `read_node(name)`, `pipeline_copy(p, node, to)`, `inspect_pipeline(p)`, `trace_nodes(p)`, `pipeline_summary(p)`, `pipeline_nodes(p)`, `pipeline_deps(p)`, `filter_node(p, pred)`, `mutate_node(p, ...)`, `union(p1, p2)`, `patch(p1, p2)`.

### `strcraft` (Strings)
`str_nchar(s)`, `str_substring(s, start, end)`, `str_replace(s, pat, repl)`, `to_lower(s)`, `to_upper(s)`, `str_trim(s)`, `str_join(xs, sep)`, `str_split(s, sep)`, `str_detect(s, pat)`, `str_extract(s, pat)`.

---

## 3. Key Principles

1. **Data-First**: Always `function(data, ...)`.
2. **No Null**: Use `NA` for missingness and `VError` for failures.
3. **Reproducibility**: Favor pipelines over monolithic scripts.
4. **Explicitness**: No implicit side effects; all dependencies must be declared.
5. **Nix-Powered**: Environments and sandboxes are managed by Nix via `tproject.toml`.

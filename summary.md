# LLM Context: The T Programming Language

The **T Programming Language** is an experimental, reproducibility-first functional language designed for declarative data analysis. It aims to reduce bugs and ensure strict reproducibility by mandating that high-level workflows are executed as statically defined **Pipelines** powered by **Nix**.

## Core Concepts

- **Reproducibility First**: Packages and environments are defined using Nix flakes.
- **Mandatory Pipelines**: Non-interactive execution requires defining a `pipeline`, enforcing DAG-based computation to prevent spaghetti code. 
- **Polyglot Architecture**: T orchestrates code. You can have `node` blocks that run natively in T, or external blocks (`rn()` for R, `pyn()` for Python). 
- **Object Interchange**: T uses Apache Arrow for data frames and PMML for models, passing data natively between R, Python, and T without serialization overhead or loss of fidelity.
- **Immutability and No Loops**: T has no loops and no mutable variables.
- **Explicit NA Handling**: NA does not propagate silently; if NA is encountered in aggregation functions without `na_rm = true`, an error is thrown. 
- **Non-Standard Evaluation (NSE)**: Uses `$` prefix for referring to variables/columns concisely (e.g. `filter($age > 30)`).

## Basic Syntax

```t
-- Variable assignment
x = 10
name = "Alice"

-- Function definition (lambda style preferred)
add = \(a, b) a + b

-- Conditionals
result = if (x > 5) "high" else "low"

-- Pipe operators
-- |> passes left-hand to right-hand, short-circuits on Error
-- ?|> forwards left-hand to right-hand even if it is an Error for recovery
[1, 2, 3] |> map(\(v) v * v) |> sum
```

## Data Manipulation (Data Verbs)

T includes a standard library (`colcraft`) for data manipulation with dplyr-like verbs:

- `select($col1, $col2)`: Select columns
- `filter($age > 25)`: Filter rows
- `mutate($bonus = $salary * 0.1)`: Create/modify columns using NSE lambdas
- `arrange($age, "desc")`: Sort rows
- `group_by($dept)`: Group data for aggregation
- `summarize($avg = mean($salary))`: Aggregate data per group

Example:
```t
df = read_csv("data.csv")
result = df
  |> filter($age >= 18)
  |> group_by($category)
  |> summarize($avg_spend = mean($spend, na_rm = true), $count = nrow($category))
```

## Pipelines and Polyglot Nodes

A script is executed by building a pipeline:

```t
p = pipeline {
  -- Native T node
  data = node(command = read_csv("data.csv") |> filter($age > 18))
  
  -- R statistical node
  model_r = rn(
    command = <{
      lm(score ~ age + income, data = data)
    }>,
    serializer = "pmml"
  )
  
  -- Python ML node
  model_py = pyn(
    command = <{
      from sklearn.ensemble import RandomForestRegressor
      RandomForestRegressor().fit(X, y)
    }>,
    serializer = "pmml"
  )
  
  -- Native predictions in T using PMML models
  predictions = node(
    command = test_data |> mutate($pred = predict(model_r, test_data))
  )
}

build_pipeline(p)
```

Instead of inlining code with `command`, nodes can point to an external file using the `script` argument. `script` and `command` are mutually exclusive. The runtime is auto-detected from the file extension (`.R` → R, `.py` → Python):

```t
p = pipeline {
  model = rn(script = "train_model.R", serializer = "pmml")
  predictions = pyn(script = "predict.py", deserializer = "pmml")
}
```

Pipeline operations allow composing, transforming, and inspecting pipelines without rebuilding them from scratch:

```t
-- Set operations
p_full = p_etl |> union(p_model)          -- merge (errors on name collision)
p_trimmed = p_full |> difference(p_debug) -- remove nodes by name
p_shared = p1 |> intersect(p2)            -- keep nodes present in both
p_updated = p_prod |> patch(p_overrides)  -- update existing nodes only

-- DAG operations
p2 = p |> swap("model", new_model)        -- replace implementation, keep edges
p2 = p |> rewire("model", replace = list(data = "data_v2"))
p2 = p |> prune                           -- remove leaf nodes
p2 = p |> upstream_of("model")            -- ancestors of a node
p2 = p |> downstream_of("clean")          -- descendants of a node

-- Composition
p_full = p_etl |> chain(p_model)          -- connect two pipelines (requires shared refs)
p_both = parallel(p_r_model, p_py_model)  -- merge independent pipelines

-- Inspection
pipeline_nodes(p)      -- list of node names
pipeline_deps(p)       -- dependency graph as Dict
pipeline_to_frame(p)   -- DataFrame with one row per node
pipeline_dot(p)        -- Graphviz DOT string for visualization

-- Validation
pipeline_validate(p)   -- returns list of errors; never throws
p |> pipeline_assert   -- throws on first error; returns pipeline if valid
```

## Core Standard Library Signatures

### Core & Math
- `print(value :: Any) :: Null`
- `type(value :: Any) :: String`
- `length(list :: List) :: Int`
- `map(list :: List, fn :: Function) :: List`
- `filter(list :: List, fn :: Function) :: List`
- `sum(list :: List, na_rm = false) :: Number`
- `pow(base :: Number, exp :: Number) :: Float`
- `sqrt(value :: Number) :: Float`
- `abs(value :: Number) :: Number`

### Base
- `is_na(value :: Any) :: Bool`
- `na_int()`, `na_float()`, `na_string()`, `na_bool()`
- `is_error(value :: Any) :: Bool`
- `error(message :: String) :: Error`

### Stats
- `mean(vector :: Vector, na_rm = false) :: Float`
- `sd(vector :: Vector, na_rm = false) :: Float`
- `quantile(vector :: Vector, prob :: Float, na_rm = false) :: Float`
- `cor(v1 :: Vector, v2 :: Vector, na_rm = false) :: Float`
- `lm(data :: DataFrame, formula :: Formula) :: Model`
- `predict(model :: Model, data :: DataFrame) :: Vector`

### DataFrame
- `read_csv(path :: String, clean_colnames = false) :: DataFrame`
- `write_csv(df :: DataFrame, path :: String) :: Null`
- `nrow(df :: DataFrame) :: Int`
- `ncol(df :: DataFrame) :: Int`
- `colnames(df :: DataFrame) :: List[String]`

### Pipeline

#### Node Constructors
- `node(command :: Any, script :: String, runtime = "T", serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`
- `pyn(command :: Any, script :: String, serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`
- `rn(command :: Any, script :: String, serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`

`command` and `script` are mutually exclusive. When `script` is used, the runtime is auto-detected from the file extension (`.R` → R, `.py` → Python) if not set explicitly.

#### Execution
- `populate_pipeline(pipeline :: Pipeline, build = false) :: Null`
- `build_pipeline(pipeline :: Pipeline) :: Null`
- `pipeline_run(pipeline :: Pipeline) :: Pipeline`

#### Inspection
- `pipeline_nodes(p :: Pipeline) :: List[String]`
- `pipeline_deps(p :: Pipeline) :: Dict`
- `pipeline_to_frame(p :: Pipeline) :: DataFrame`
- `pipeline_edges(p :: Pipeline) :: List[List[String]]`
- `pipeline_roots(p :: Pipeline) :: List[String]`
- `pipeline_leaves(p :: Pipeline) :: List[String]`
- `pipeline_depth(p :: Pipeline) :: Int`
- `pipeline_cycles(p :: Pipeline) :: List[String]`
- `pipeline_print(p :: Pipeline) :: Null`
- `pipeline_dot(p :: Pipeline) :: String`
- `read_node(name :: String, which_log = null) :: Any`

#### Validation
- `pipeline_validate(p :: Pipeline) :: List[String]`
- `pipeline_assert(p :: Pipeline) :: Pipeline`

#### Node Manipulation
- `filter_node(p :: Pipeline, predicate :: Function) :: Pipeline`
- `mutate_node(p :: Pipeline, ..., where :: Function) :: Pipeline`
- `rename_node(p :: Pipeline, old_name :: String, new_name :: String) :: Pipeline`
- `select_node(p :: Pipeline, ...) :: DataFrame`
- `arrange_node(p :: Pipeline, field :: Symbol, direction = "asc") :: Pipeline`

#### Set Operations
- `union(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`
- `difference(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`
- `intersect(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`
- `patch(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`

#### DAG-Aware Transformations
- `swap(p :: Pipeline, name :: String, new_node :: Node) :: Pipeline`
- `rewire(p :: Pipeline, name :: String, replace :: List[String]) :: Pipeline`
- `prune(p :: Pipeline) :: Pipeline`
- `upstream_of(p :: Pipeline, name :: String) :: Pipeline`
- `downstream_of(p :: Pipeline, name :: String) :: Pipeline`
- `subgraph(p :: Pipeline, name :: String) :: Pipeline`

#### Composition
- `chain(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`
- `parallel(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`

## Metaprogramming
- `expr(code)`: Quotation block capturing code as an AST.
- `!!value`: Unquote single value into `expr`.
- `!!!list`: Unquote-splice a list into `expr`.
- `eval(expr)`: Evaluates a quoted expression.

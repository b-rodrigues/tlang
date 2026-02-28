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
- `node(command :: Any, runtime = "T", serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`
- `pyn(command, serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`
- `rn(command, serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`
- `populate_pipeline(pipeline :: Pipeline, build = false) :: Null`
- `build_pipeline(pipeline :: Pipeline) :: Null`
- `read_node(name :: String, which_log = null) :: Any`
- `pipeline_run(pipeline :: Pipeline) :: Pipeline`

## Metaprogramming
- `expr(code)`: Quotation block capturing code as an AST.
- `!!value`: Unquote single value into `expr`.
- `!!!list`: Unquote-splice a list into `expr`.
- `eval(expr)`: Evaluates a quoted expression.

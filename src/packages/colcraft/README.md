# colcraft

DataFrame manipulation verbs, inspired by dplyr.

## Functions

| Function | Description |
|----------|-------------|
| `select(df, ...)` | Select columns by name |
| `filter(df, predicate)` | Filter rows by condition |
| `mutate(df, name = expr)` | Add or transform columns |
| `arrange(df, col)` | Sort rows by column |
| `group_by(df, ...)` | Group by one or more columns |
| `ungroup(df)` | Remove grouping |
| `summarize(df, ...)` | Aggregate grouped data |

## NSE (Non-Standard Evaluation)

Column references use `$` syntax:

```t
df |> filter($age > 30)
df |> mutate(bmi = $weight / pow($height, 2))
df |> arrange($name)
```

## Examples

```t
data = read_csv("employees.csv")

data |> select($name, $department, $salary)
     |> filter($salary > 50000)
     |> group_by($department)
     |> summarize(avg_salary = mean($salary))
     |> arrange($avg_salary)
```

## Status

Built-in package — included with T by default.

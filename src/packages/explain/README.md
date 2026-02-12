# explain

Value introspection and intent blocks.

## Functions

| Function | Description |
|----------|-------------|
| `explain(x)` | Return a dict describing a value's type, structure, and metadata |
| `explain_json(x)` | Return the explanation as a JSON string |
| `intent_fields(i)` | Get the field names from an intent block |
| `intent_get(i, key)` | Get a specific field value from an intent block |

## Intent Blocks

Intent blocks attach metadata to values:

```t
result = data |> summarize(total = sum($amount))

why = intent {
  goal = "Calculate total sales"
  method = "Sum of amount column"
  source = "sales.csv"
}

intent_fields(why)         -- ["goal", "method", "source"]
intent_get(why, "goal")    -- "Calculate total sales"
```

## Examples

```t
explain(42)           -- {type: "Int", value: "42"}
explain([1, 2, 3])    -- {type: "List", length: 3, ...}
explain_json(42)      -- JSON string
```

## Status

Built-in package — included with T by default.

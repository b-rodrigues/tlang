# Tutorial: Using script paths in `node()`, `pyn()`, and `rn()`

`script` is a **path to a script file**, not an inline `<{ ... }>` block.

## Core rules

- Use **either** `command` **or** `script`.
- If both are supplied, T returns:

```text
Error(ArityError: "Provide either `command` or `script`, but not both.")
```

## Python script path

Provide a `.py` file path. The script should either:

- define `main()` and return the node object, or
- set a global variable named `result`.

Example `my_node.py`:

```python
def main():
    vals = [1, 2, 3]
    return {"sum": sum(vals), "n": len(vals)}
```

Use it from T:

```t
p = pipeline {
  py_model = pyn(script = "my_node.py")
}
```

## R script path

Provide an `.R` file path. The value of the script's **last expression** is serialized.

Example `my_node.R`:

```r
vals <- c(1, 2, 3)
list(sum = sum(vals), n = length(vals))
```

Use it from T:

```t
p = pipeline {
  r_model = rn(script = "my_node.R")
}
```

## Explicit `node()` usage

```t
p = pipeline {
  py_model = node(runtime = Python, script = "my_node.py")
  r_model  = node(runtime = R, script = "my_node.R")
}
```

## Invalid usage

```t
# ❌ invalid
pyn(command = <{ 1 + 1 }>, script = "my_node.py")
```

```t
# ✅ valid
pyn(script = "my_node.py")
```

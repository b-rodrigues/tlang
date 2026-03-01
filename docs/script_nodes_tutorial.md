# Tutorial: Using `script` vs `command` in `node()`, `pyn()`, and `rn()`

This tutorial explains how to choose between `command` and `script` for pipeline nodes.

## Rule of thumb

For cross-runtime nodes (`Python` and `R`):

- Use **`command`** for expression-style code.
- Use **`script`** for black-box script-style code that may have multiple statements.
- Provide **exactly one** of `command` or `script`.

If both are provided, T raises:

```text
Error(ArityError: "Provide either `command` or `script`, but not both.")
```

## Why `script` exists

Sometimes a node is easier to write as imperative code (loops, branches, temporary variables, function definitions, etc.).

`script` lets you treat the body as a black box, as long as one final object is returned and serialized as the node artifact.

## Python examples

### 1) Expression-style with `command`

```t
p = pipeline {
  features = pyn(command = <{ [1, 2, 3] }>)
}
```

### 2) Script-style with `script`

```t
p = pipeline {
  model = pyn(script = <{
import math
vals = [1, 4, 9]
rooted = [math.sqrt(x) for x in vals]
return {"values": vals, "sqrt": rooted}
  }>)
}
```

## R examples

### 1) Expression-style with `command`

```t
p = pipeline {
  x = rn(command = <{ 1 + 1 }>)
}
```

### 2) Script-style with `script`

```t
p = pipeline {
  summary = rn(script = <{
vals <- c(1, 2, 3, 4)
out <- list(mean = mean(vals), sum = sum(vals))
out
  }>)
}
```

## Base `node()` form

You can also use explicit runtime configuration:

```t
p = pipeline {
  result = node(runtime = Python, script = <{
nums = [1, 2, 3]
return {"n": len(nums), "sum": sum(nums)}
  }>)
}
```

## Invalid usage

Do not pass both:

```t
# ❌ invalid
pyn(command = <{ 1 + 1 }>, script = <{ return 2 }>)
```

Use one or the other:

```t
# ✅ valid
pyn(command = <{ 1 + 1 }>)
# or
pyn(script = <{ return 2 }>)
```

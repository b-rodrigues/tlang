# rm

Remove objects from the environment

Removes one or more variables from the current environment by name. Supports bare symbols (R-style selective removal), strings, and lists of names via the `list` parameter.

## Parameters

- **...** (`Symbol | String`): One or more variables to remove.

- **list** (`List[String]`): (Optional) A list of variable names to remove.


## Returns



## Examples

```t
x = 10; y = 20
rm(x, y)          -- Removes x and y

z = 30
rm("z")           -- Removes z

vars = ["a", "b"]
rm(list = vars)   -- Removes variables 'a' and 'b'

```


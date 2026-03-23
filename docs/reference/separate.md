# separate

Separate a character column into multiple columns

Given either a regular expression or a fixed position, separate() splits a single character column into multiple new columns.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **col** (`Symbol`): The column to separate (use $col syntax).

- **into** (`List[String]`): Names of the new columns to create.

- **sep** (`String`): (Optional) Regular expression or position to separate at.

- **remove** (`Bool`): (Optional) If true, remove the input column from the result.


## Returns

The separated DataFrame.

## Examples

```t
separate(df, $date, into = ["year", "month", "day"], sep = "-")
```


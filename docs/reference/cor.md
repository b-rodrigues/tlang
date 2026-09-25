# cor

Correlation

Computes the correlation coefficient between two vectors. `method = "pearson"` (default) is the linear correlation. `method = "spearman"` ranks values first (average ranks for ties), then computes Pearson on ranks.

## Parameters

- **x** (`Vector`): | List First numeric vector.

- **y** (`Vector`): | List Second numeric vector.

- **na_rm** (`Bool`): (Optional) Should missing values be removed? Default is false.

- **weights** (`Vector[Float]`): | List[Float] = NA Optional non-negative observation weights (Pearson only).

- **method** (`String`): = "pearson" Correlation method: "pearson" or "spearman".


## Returns

The correlation coefficient (-1 to 1).

## Examples

```t
cor(mtcars["mpg"], mtcars["wt"])
```


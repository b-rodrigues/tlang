# cor

Correlation

Computes the Pearson correlation coefficient between two vectors.

## Parameters

- **x** (`Vector`): | List First numeric vector.
- **y** (`Vector`): | List Second numeric vector.
- **na_rm** (`Bool`): (Optional) Should missing values be removed? Default is false.

## Returns

The correlation coefficient (-1 to 1).

## Examples

```t
cor(mtcars["mpg"], mtcars["wt"])
```


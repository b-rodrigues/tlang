# poly

Polynomial basis expansion

Generates a basis of polynomial terms for a numeric vector.

## Parameters

- **x** (`Vector[Number]`): | List[Number] The vector to expand.
- **degree** (`Int`): The degree of the polynomial.
- **raw** (`Bool`): = false If true, return raw powers instead of orthogonal polynomials.

## Returns:

Returns: A named list of polynomial terms.

## Examples

```t
mutate(df, !!!poly($age, 3, raw = true))
```


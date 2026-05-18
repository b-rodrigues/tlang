# winsorize

Winsorize values

Clamp tails to specified quantile limits.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **limits** (`Float`): | Vector[Float] One-sided or (lo, hi) limits in [0, 0.5).

- **na_rm** (`Bool`): = false Remove NA values first.

- **weights** (`Vector[Float]`): | List[Float] = NA Optional non-negative observation weights used to determine the cut points.


## Returns

| Vector Computed result (scalar or vectorized).


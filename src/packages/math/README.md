# math

Pure numerical primitives.

## Functions

| Function | Description |
|----------|-------------|
| `sqrt(x)` | Square root |
| `abs(x)` | Absolute value |
| `log(x)` | Natural logarithm |
| `exp(x)` | Exponential (e^x) |
| `pow(base, exp)` | Exponentiation |
| `round(x, digits = 0)` | Round to decimal digits |
| `floor(x)` | Floor function |
| `ceiling(x)` / `ceil(x)` | Ceiling function |
| `trunc(x)` | Truncate fractional part |
| `sign(x)` | Sign of value (-1, 0, 1) |
| `signif(x, digits)` | Significant-figure rounding |
| `sin(x)`, `cos(x)`, `tan(x)` | Trigonometric functions |
| `asin(x)`, `acos(x)`, `atan(x)` | Inverse trigonometric functions |
| `atan2(y, x)` | Two-argument arctangent |
| `sinh(x)`, `cosh(x)`, `tanh(x)` | Hyperbolic trig |
| `asinh(x)`, `acosh(x)`, `atanh(x)` | Inverse hyperbolic trig |
| `ndarray(data, shape)` | Create an N-dimensional array |
| `reshape(arr, shape)` | Reshape an NDArray |
| `matmul(a, b)` | Matrix multiplication |
| `inv(matrix)` | Matrix inversion |
| `transpose(matrix)` | Matrix transpose |
| `diag(x)` | Create or extract diagonal |
| `iota(n)` | Sequence of integers |

## Examples

```t
sqrt(16)      -- 4.0
abs(-5)       -- 5
log(1)        -- 0.0
exp(1)        -- 2.71828...
pow(2, 10)    -- 1024.0
```

## Status

Built-in package — included with T by default.

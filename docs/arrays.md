# Numerical Arrays (NDArrays)

Numerical arrays (NDArrays) are first-class data structures in T designed for high-performance numerical computation, linear algebra, and statistical operations. Unlike lists, NDArrays have a fixed shape and optimized storage for numeric data.

## Creating Arrays

You can create an NDArray using the `ndarray()` function. It can infer the shape from a nested list or accept an explicit shape.

### From Nested Lists
```t
-- Create a 1D array (vector)
v = ndarray([1, 2, 3, 4, 5])

-- Create a 2D array (matrix)
m = ndarray([[1, 2, 3], [4, 5, 6]])

-- Access shape and data
print(shape(m))        -- [2, 3]
print(ndarray_data(m)) -- [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
```

### With Explicit Shape
```t
-- Create a 2x3 matrix from a flat list
m = ndarray([1, 2, 3, 4, 5, 6], shape = [2, 3])
```

## Array Operations

### Element-wise Arithmetic
NDArrays support standard arithmetic operators (+, -, *, /) and comparison operators (==, !=, <, >, <=, >=). These operations are applied element-wise.

```t
a = ndarray([[1, 2], [3, 4]])
b = ndarray([[5, 6], [7, 8]])

c = a + b    -- [[6, 8], [10, 12]]
d = a * 2    -- [[2, 4], [6, 8]] (Broadcasting)
```

### Broadcasting
Operations between an NDArray and a scalar value automatically "broadcast" the scalar to match the shape of the array.

```t
m = ndarray([1, 2, 3])
res = m + 10  -- [11, 12, 13]
```

### Linear Algebra
T provides specific functions for matrix operations:

- **`matmul(a, b)`**: Performs matrix multiplication between two 2D arrays.
- **`kron(a, b)`**: Computes the Kronecker product of two 2D arrays.

```t
a = ndarray([[1, 2], [3, 4]])
i = ndarray([[1, 0], [0, 1]])

res = matmul(a, i) -- Returns 'a'
```

## Reshaping and Introspection

- **`shape(arr)`**: Returns the dimensions of the array as a list.
- **`ndarray_data(arr)`**: Returns the underlying flat data as a list of floats.
- **`reshape(arr, new_shape)`**: Returns a new array with the same data but a different shape. The total number of elements must remain consistent.

```t
m = ndarray([1, 2, 3, 4, 5, 6], shape = [2, 3])
m2 = m |> reshape([3, 2]) -- Reshapes to 3 rows, 2 columns
```

## Best Practices
- NDArrays cannot contain `NA` values. Handle missing data before converting to arrays.
- Prefer NDArrays over lists for large numerical datasets to benefit from optimized performance and specialized linear algebra functions.

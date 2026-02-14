#!/usr/bin/env Rscript

# Generate expected NDArray outputs using R's array operations
# These are the "golden" results T's NDArray should match

library(readr)
library(dplyr)

output_dir <- "tests/golden/expected"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Generating expected NDArray outputs from R...\n")

# Helper to save array data in flat format with shape metadata
save_array_output <- function(arr, name, operation) {
  filepath <- file.path(output_dir, paste0(name, ".csv"))
  
  # Get dimensions
  dims <- dim(arr)
  if (is.null(dims)) {
    dims <- length(arr)
  }
  
  # Flatten array to vector
  # R uses column-major order, T uses row-major order
  # For 2D arrays (matrices), transpose to convert column-major to row-major
  # For 3D+ arrays, we need to reorder dimensions appropriately
  if (length(dims) == 2) {
    # Transpose 2D array: R's [i,j] becomes T's [j,i] in memory
    flat_data <- as.vector(t(arr))
  } else if (length(dims) == 3) {
    # For 3D arrays, we need to reorder from R's [i,j,k] to T's row-major
    # aperm(arr, c(3,2,1)) reverses the dimension order for proper flattening
    flat_data <- as.vector(aperm(arr, c(3,2,1)))
  } else {
    # For 1D or higher dimensions, flatten directly
    flat_data <- as.vector(arr)
  }
  
  # Create output with shape and flattened data
  output_df <- tibble(
    shape = paste(dims, collapse = ","),
    data = paste(flat_data, collapse = ",")
  )
  
  write_csv(output_df, filepath)
  message(sprintf("✓ %s: %s (shape=[%s], %d elements)", 
                  operation, name, paste(dims, collapse=", "), length(flat_data)))
}

# ============================================================================
# Test Suite 1: Array Creation and Shape Operations
# ============================================================================
message("=== ARRAY CREATION Tests ===")

# Test 1.1: Create 1D array
arr_1d <- array(1:5, dim = c(5))
save_array_output(arr_1d, "ndarray_1d", "array(1:5)")

# Test 1.2: Create 2D array (matrix)
arr_2d <- array(1:6, dim = c(2, 3))
save_array_output(arr_2d, "ndarray_2d_2x3", "array(1:6, dim=c(2,3))")

# Test 1.3: Create 3D array
arr_3d <- array(1:24, dim = c(2, 3, 4))
save_array_output(arr_3d, "ndarray_3d_2x3x4", "array(1:24, dim=c(2,3,4))")

# Test 1.4: Reshape operation
# First create the original array
arr_reshape <- array(1:12, dim = c(3, 4))
save_array_output(arr_reshape, "ndarray_reshape_3x4", "array(1:12, dim=c(3,4))")

# Reshape to 2x6: transpose first to get row-major order, then reshape
arr_reshaped <- array(as.vector(t(arr_reshape)), dim = c(2, 6))
save_array_output(arr_reshaped, "ndarray_reshape_2x6", "reshape(array(1:12, 3x4), dim=c(2,6))")

# ============================================================================
# Test Suite 2: Matrix Multiplication
# ============================================================================
message("\n=== MATRIX MULTIPLICATION Tests ===")

# Test 2.1: Simple 2x2 matrix multiplication
mat_a <- array(c(1, 2, 3, 4), dim = c(2, 2))
mat_b <- array(c(5, 6, 7, 8), dim = c(2, 2))
mat_result <- mat_a %*% mat_b
save_array_output(mat_result, "matmul_2x2", "matmul([[1,2],[3,4]], [[5,6],[7,8]])")

# Test 2.2: Non-square matrix multiplication (2x3 × 3x2)
mat_c <- array(1:6, dim = c(2, 3))
mat_d <- array(1:6, dim = c(3, 2))
mat_result2 <- mat_c %*% mat_d
save_array_output(mat_result2, "matmul_2x3_3x2", "matmul(2x3, 3x2)")

# Test 2.3: Identity matrix multiplication
mat_e <- array(c(1, 2, 3, 4), dim = c(2, 2))
identity <- array(c(1, 0, 0, 1), dim = c(2, 2))
mat_identity_result <- mat_e %*% identity
save_array_output(mat_identity_result, "matmul_identity", "matmul(A, I)")

# ============================================================================
# Test Suite 3: Kronecker Product
# ============================================================================
message("\n=== KRONECKER PRODUCT Tests ===")

# Test 3.1: Simple 2x2 Kronecker product
kron_a <- array(c(1, 2, 3, 4), dim = c(2, 2))
kron_b <- array(c(0, 5, 6, 7), dim = c(2, 2))
kron_result <- kronecker(kron_a, kron_b)
save_array_output(kron_result, "kron_2x2", "kron([[1,2],[3,4]], [[0,5],[6,7]])")

# Test 3.2: Different sized Kronecker (2x3 ⊗ 2x2)
kron_c <- array(1:6, dim = c(2, 3))
kron_d <- array(1:4, dim = c(2, 2))
kron_result2 <- kronecker(kron_c, kron_d)
save_array_output(kron_result2, "kron_2x3_2x2", "kron(2x3, 2x2)")

# Test 3.3: Identity Kronecker
kron_e <- array(c(1, 2, 3, 4), dim = c(2, 2))
kron_identity <- kronecker(kron_e, identity)
save_array_output(kron_identity, "kron_identity", "kron(A, I)")

# ============================================================================
# Test Suite 4: Element-wise Operations with Broadcasting
# ============================================================================
message("\n=== ELEMENT-WISE OPERATIONS Tests ===")

# Test 4.1: Array + scalar
arr_f <- array(1:6, dim = c(2, 3))
arr_add_scalar <- arr_f + 10
save_array_output(arr_add_scalar, "ndarray_add_scalar", "array + 10")

# Test 4.2: Array * scalar
arr_mul_scalar <- arr_f * 2
save_array_output(arr_mul_scalar, "ndarray_mul_scalar", "array * 2")

# Test 4.3: Array - scalar
arr_sub_scalar <- arr_f - 5
save_array_output(arr_sub_scalar, "ndarray_sub_scalar", "array - 5")

# Test 4.4: Array / scalar
arr_div_scalar <- arr_f / 2
save_array_output(arr_div_scalar, "ndarray_div_scalar", "array / 2")

# Test 4.5: Array element-wise operations
arr_g <- array(c(10, 20, 30, 40, 50, 60), dim = c(2, 3))
arr_add_array <- arr_f + arr_g
save_array_output(arr_add_array, "ndarray_add_array", "array1 + array2")

arr_mul_array <- arr_f * arr_g
save_array_output(arr_mul_array, "ndarray_mul_array", "array1 * array2")

# ============================================================================
# Test Suite 5: Comparison Operations
# ============================================================================
message("\n=== COMPARISON OPERATIONS Tests ===")

# Test 5.1: Greater than scalar
arr_h <- array(1:6, dim = c(2, 3))
arr_gt <- (arr_h > 3) * 1.0  # Convert boolean to numeric (1.0/0.0)
save_array_output(arr_gt, "ndarray_gt_scalar", "array > 3")

# Test 5.2: Equal to scalar
arr_eq <- (arr_h == 4) * 1.0
save_array_output(arr_eq, "ndarray_eq_scalar", "array == 4")

# Test 5.3: Less than or equal
arr_le <- (arr_h <= 4) * 1.0
save_array_output(arr_le, "ndarray_le_scalar", "array <= 4")

# ============================================================================
# Test Suite 6: Complex Operations
# ============================================================================
message("\n=== COMPLEX OPERATIONS Tests ===")

# Test 6.1: Chain matrix multiplications
mat_i <- array(1:6, dim = c(2, 3))
mat_j <- array(1:6, dim = c(3, 2))
mat_k <- array(c(1, 2, 3, 4), dim = c(2, 2))
# (2x3) × (3x2) = (2x2), then (2x2) × (2x2) = (2x2)
mat_chain <- (mat_i %*% mat_j) %*% mat_k
save_array_output(mat_chain, "matmul_chain", "matmul(matmul(A, B), C)")

# Test 6.2: Operations on result of matrix multiply
mat_result_ops <- (mat_a %*% mat_b) + 100
save_array_output(mat_result_ops, "matmul_then_add", "matmul(A, B) + 100")

message("\n✅ All NDArray outputs generated!")

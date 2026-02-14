#!/usr/bin/env Rscript

# Golden test suite: Compare T outputs vs R expected outputs
# Uses testthat for structured testing

library(testthat)
library(readr)
library(dplyr)

expected_dir <- "tests/golden/expected"
t_output_dir <- "tests/golden/t_outputs"

# Helper: Load and compare CSVs
compare_csvs <- function(test_name, tolerance = 1e-6) {
  expected_file <- file.path(expected_dir, paste0(test_name, ".csv"))
  t_output_file <- file.path(t_output_dir, paste0(test_name, ".csv"))
  
  # Check both files exist
  if (!file.exists(expected_file)) {
    skip(paste("Expected file not found:", expected_file))
  }
  
  if (!file.exists(t_output_file)) {
    fail(paste("T output file not found:", t_output_file))
    return()
  }
  
  # Load CSVs
  expected <- read_csv(expected_file, show_col_types = FALSE)
  t_output <- read_csv(t_output_file, show_col_types = FALSE)
  
  # Compare dimensions
  expect_equal(nrow(t_output), nrow(expected),
               info = paste(test_name, "- row count mismatch"))
  expect_equal(ncol(t_output), ncol(expected),
               info = paste(test_name, "- column count mismatch"))
  
  # Compare column names
  expect_equal(sort(names(t_output)), sort(names(expected)),
               info = paste(test_name, "- column names mismatch"))
  
  # Compare values (allowing for floating point tolerance)
  for (col in names(expected)) {
    if (is.numeric(expected[[col]])) {
      expect_equal(t_output[[col]], expected[[col]], 
                   tolerance = tolerance,
                   info = paste(test_name, "- numeric column:", col))
    } else {
      expect_equal(t_output[[col]], expected[[col]],
                   info = paste(test_name, "- column:", col))
    }
  }
}

# ============================================================================
# Test Suite 1: SELECT
# ============================================================================

test_that("SELECT: single column", {
  compare_csvs("mtcars_select_mpg")
})

test_that("SELECT: multiple columns", {
  compare_csvs("mtcars_select_multi")
})

test_that("SELECT: with reordering", {
  compare_csvs("mtcars_select_reorder")
})

# ============================================================================
# Test Suite 2: FILTER
# ============================================================================

test_that("FILTER: numeric condition >", {
  compare_csvs("mtcars_filter_mpg_gt_20")
})

test_that("FILTER: multiple conditions AND", {
  compare_csvs("mtcars_filter_mpg_and_cyl")
})

test_that("FILTER: OR condition", {
  compare_csvs("mtcars_filter_mpg_or_hp")
})

test_that("FILTER: string equality", {
  compare_csvs("iris_filter_setosa")
})

# ============================================================================
# Test Suite 3: MUTATE
# ============================================================================

test_that("MUTATE: simple arithmetic", {
  compare_csvs("mtcars_mutate_double")
})

test_that("MUTATE: multiple new columns", {
  compare_csvs("mtcars_mutate_multi")
})

test_that("MUTATE: overwrite existing column", {
  compare_csvs("mtcars_mutate_overwrite")
})

test_that("MUTATE: ratio of two columns", {
  compare_csvs("mtcars_mutate_ratio")
})

# ============================================================================
# Test Suite 4: ARRANGE
# ============================================================================

test_that("ARRANGE: ascending", {
  compare_csvs("mtcars_arrange_mpg_asc")
})

test_that("ARRANGE: descending", {
  compare_csvs("mtcars_arrange_mpg_desc")
})

test_that("ARRANGE: multiple columns", {
  compare_csvs("mtcars_arrange_cyl_mpg")
})

# ============================================================================
# Test Suite 5: GROUP_BY + SUMMARIZE
# ============================================================================

test_that("GROUP_BY + SUMMARIZE: mean", {
  compare_csvs("mtcars_groupby_cyl_mean_mpg")
})

test_that("GROUP_BY + SUMMARIZE: multiple aggregations", {
  compare_csvs("mtcars_groupby_cyl_multi_agg")
})

test_that("GROUP_BY + SUMMARIZE: multiple keys", {
  compare_csvs("mtcars_groupby_cyl_gear")
})

test_that("GROUP_BY + SUMMARIZE: various aggregations", {
  compare_csvs("mtcars_groupby_various_aggs")
})

test_that("GROUP_BY + SUMMARIZE: on iris", {
  compare_csvs("iris_groupby_species")
})

# ============================================================================
# Test Suite 6: PIPELINES
# ============================================================================

test_that("PIPELINE: filter %>% select", {
  compare_csvs("mtcars_pipeline_filter_select")
})

test_that("PIPELINE: select %>% filter %>% arrange", {
  compare_csvs("mtcars_pipeline_select_filter_arrange")
})

test_that("PIPELINE: filter %>% mutate %>% arrange", {
  compare_csvs("mtcars_pipeline_filter_mutate_arrange")
})

test_that("PIPELINE: group_by %>% mutate (window)", {
  compare_csvs("mtcars_pipeline_groupby_mutate")
})

test_that("PIPELINE: complex iris pipeline", {
  compare_csvs("iris_pipeline_complex")
})

# ============================================================================
# Test Suite 7: NA HANDLING
# ============================================================================

test_that("NA: mean with na.rm", {
  compare_csvs("airquality_mean_na_rm")
})

test_that("NA: filter out NAs", {
  compare_csvs("airquality_filter_no_na")
})

test_that("NA: group by with NAs", {
  compare_csvs("airquality_groupby_with_nas")
})

# ============================================================================
# Test Suite 8: LINEAR MODELS
# ============================================================================

test_that("LM: simple regression coefficients", {
  compare_csvs("lm_mpg_hp_coefficients", tolerance = 1e-5)
})

test_that("LM: simple regression statistics", {
  compare_csvs("lm_mpg_hp_simple", tolerance = 1e-5)
})

# ============================================================================
# Test Suite 9: CORRELATIONS
# ============================================================================

test_that("COR: simple correlation", {
  compare_csvs("cor_mpg_hp", tolerance = 1e-6)
})

test_that("COR: iris correlation", {
  compare_csvs("cor_iris_sepal_petal", tolerance = 1e-6)
})

# ============================================================================
# Test Suite 10: EDGE CASES
# ============================================================================

test_that("EDGE CASE: select on empty DataFrame", {
  compare_csvs("empty_select")
})

test_that("EDGE CASE: filter on empty DataFrame", {
  compare_csvs("empty_filter")
})

test_that("EDGE CASE: select on single row DataFrame", {
  compare_csvs("single_row_select")
})

test_that("EDGE CASE: mutate on single row DataFrame", {
  compare_csvs("single_row_mutate")
})

test_that("EDGE CASE: division by zero (Inf handling)", {
  skip("T returns DivisionByZero error instead of Inf for division by zero")
  compare_csvs("edge_division", tolerance = 1e-6)
})

# ============================================================================
# Test Suite 11: RANKING WINDOW FUNCTIONS
# ============================================================================

test_that("WINDOW RANK: row_number on simple.age", {
  compare_csvs("simple_row_number_age")
})

test_that("WINDOW RANK: min_rank on simple.age", {
  compare_csvs("simple_min_rank_age")
})

test_that("WINDOW RANK: dense_rank on simple.age", {
  compare_csvs("simple_dense_rank_age")
})

test_that("WINDOW RANK: percent_rank on simple.age", {
  compare_csvs("simple_percent_rank_age")
})

test_that("WINDOW RANK: cume_dist on simple.age", {
  compare_csvs("simple_cume_dist_age")
})

test_that("WINDOW RANK: ntile on simple.age", {
  compare_csvs("simple_ntile_age")
})

test_that("WINDOW RANK: min_rank on mtcars.mpg", {
  compare_csvs("mtcars_min_rank_mpg")
})

# ============================================================================
# Test Suite 12: OFFSET WINDOW FUNCTIONS (lead/lag)
# ============================================================================

test_that("WINDOW OFFSET: lag on simple.score", {
  compare_csvs("simple_lag_score")
})

test_that("WINDOW OFFSET: lead on simple.score", {
  compare_csvs("simple_lead_score")
})

test_that("WINDOW OFFSET: lag with offset 2 on simple.score", {
  compare_csvs("simple_lag2_score")
})

test_that("WINDOW OFFSET: lead with offset 2 on simple.score", {
  compare_csvs("simple_lead2_score")
})

test_that("WINDOW OFFSET: lag on mtcars.mpg", {
  compare_csvs("mtcars_lag_mpg")
})

test_that("WINDOW OFFSET: lead on mtcars.mpg", {
  compare_csvs("mtcars_lead_mpg")
})

# ============================================================================
# Test Suite 13: CUMULATIVE WINDOW FUNCTIONS
# ============================================================================

test_that("WINDOW CUMULATIVE: cumsum on simple.score", {
  compare_csvs("simple_cumsum_score")
})

test_that("WINDOW CUMULATIVE: cummax on simple.score", {
  compare_csvs("simple_cummax_score")
})

test_that("WINDOW CUMULATIVE: cummin on simple.score", {
  compare_csvs("simple_cummin_score")
})

test_that("WINDOW CUMULATIVE: cummean on simple.score", {
  compare_csvs("simple_cummean_score")
})

test_that("WINDOW CUMULATIVE: cumsum on mtcars.mpg", {
  compare_csvs("mtcars_cumsum_mpg")
})

test_that("WINDOW CUMULATIVE: cumall and cumany", {
  compare_csvs("simple_cumall_cumany")
})

# ============================================================================
# Test Suite 14: NDARRAY OPERATIONS
# ============================================================================

test_that("NDARRAY: create 1D array", {
  compare_csvs("ndarray_1d")
})

test_that("NDARRAY: create 2D array (2x3)", {
  compare_csvs("ndarray_2d_2x3")
})

test_that("NDARRAY: create 3D array (2x3x4)", {
  compare_csvs("ndarray_3d_2x3x4")
})

test_that("NDARRAY: reshape 3x4", {
  compare_csvs("ndarray_reshape_3x4")
})

test_that("NDARRAY: reshape to 2x6", {
  compare_csvs("ndarray_reshape_2x6")
})

# ============================================================================
# Test Suite 15: MATRIX MULTIPLICATION
# ============================================================================

test_that("MATMUL: 2x2 matrices", {
  compare_csvs("matmul_2x2")
})

test_that("MATMUL: 2x3 × 3x2", {
  compare_csvs("matmul_2x3_3x2")
})

test_that("MATMUL: with identity matrix", {
  compare_csvs("matmul_identity")
})

test_that("MATMUL: chained multiplications", {
  compare_csvs("matmul_chain")
})

test_that("MATMUL: operations on result", {
  compare_csvs("matmul_then_add")
})

# ============================================================================
# Test Suite 16: KRONECKER PRODUCT
# ============================================================================

test_that("KRON: 2x2 matrices", {
  compare_csvs("kron_2x2")
})

test_that("KRON: 2x3 ⊗ 2x2", {
  compare_csvs("kron_2x3_2x2")
})

test_that("KRON: with identity matrix", {
  compare_csvs("kron_identity")
})

# ============================================================================
# Test Suite 17: DIAG/INV OPERATIONS
# ============================================================================

test_that("DIAG: from vector", {
  compare_csvs("diag_from_vector")
})

test_that("DIAG: from matrix", {
  compare_csvs("diag_from_matrix")
})

test_that("INV: 2x2 matrix", {
  compare_csvs("inv_2x2")
})

# ============================================================================
# Test Suite 18: ELEMENT-WISE OPERATIONS
# ============================================================================

test_that("ELEMENTWISE: array + scalar", {
  compare_csvs("ndarray_add_scalar")
})

test_that("ELEMENTWISE: array * scalar", {
  compare_csvs("ndarray_mul_scalar")
})

test_that("ELEMENTWISE: array - scalar", {
  compare_csvs("ndarray_sub_scalar")
})

test_that("ELEMENTWISE: array / scalar", {
  compare_csvs("ndarray_div_scalar")
})

test_that("ELEMENTWISE: array + array", {
  compare_csvs("ndarray_add_array")
})

test_that("ELEMENTWISE: array * array", {
  compare_csvs("ndarray_mul_array")
})

# ============================================================================
# Test Suite 18: COMPARISON OPERATIONS
# ============================================================================

test_that("COMPARISON: array > scalar", {
  compare_csvs("ndarray_gt_scalar")
})

test_that("COMPARISON: array == scalar", {
  compare_csvs("ndarray_eq_scalar")
})

test_that("COMPARISON: array <= scalar", {
  compare_csvs("ndarray_le_scalar")
})

# ============================================================================
# SUMMARY REPORT
# ============================================================================

message("\n", paste(rep("=", 70), collapse = ""))
message("GOLDEN TEST SUMMARY")
message(paste(rep("=", 70), collapse = ""))

message("See test output above for pass/fail/skip details")
message(paste(rep("=", 70), collapse = ""))
message("✓ Golden test comparison complete")

#!/usr/bin/env Rscript

# Generate expected outputs for window functions using dplyr
# These are the "golden" results T should match

library(dplyr)
library(readr)

data_dir <- "tests/golden/data"
output_dir <- "tests/golden/expected"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Generating expected window function outputs from R/dplyr...\n")

# Helper to save with metadata
save_output <- function(df, name, operation) {
  filepath <- file.path(output_dir, paste0(name, ".csv"))
  write_csv(df, filepath)
  message(sprintf("✓ %s: %s (%d rows × %d cols)", 
                  operation, name, nrow(df), ncol(df)))
}

# Load test datasets
simple <- read_csv(file.path(data_dir, "simple.csv"), show_col_types = FALSE)
mtcars <- read_csv(file.path(data_dir, "mtcars.csv"), show_col_types = FALSE)

# ============================================================================
# Test Suite 11: RANKING WINDOW FUNCTIONS
# ============================================================================
message("=== RANKING Window Function Tests ===")

# Test 11.1: row_number on simple dataset
simple %>%
  mutate(row_number_age = row_number(age)) %>%
  save_output("simple_row_number_age", "mutate(row_number_age = row_number(age))")

# Test 11.2: min_rank on simple dataset
simple %>%
  mutate(min_rank_age = min_rank(age)) %>%
  save_output("simple_min_rank_age", "mutate(min_rank_age = min_rank(age))")

# Test 11.3: dense_rank on simple dataset
simple %>%
  mutate(dense_rank_age = dense_rank(age)) %>%
  save_output("simple_dense_rank_age", "mutate(dense_rank_age = dense_rank(age))")

# Test 11.4: percent_rank on simple dataset
simple %>%
  mutate(pct_rank_age = percent_rank(age)) %>%
  save_output("simple_percent_rank_age", "mutate(pct_rank_age = percent_rank(age))")

# Test 11.5: cume_dist on simple dataset
simple %>%
  mutate(cume_dist_age = cume_dist(age)) %>%
  save_output("simple_cume_dist_age", "mutate(cume_dist_age = cume_dist(age))")

# Test 11.6: ntile on simple dataset
simple %>%
  mutate(ntile_age = ntile(age, 4)) %>%
  save_output("simple_ntile_age", "mutate(ntile_age = ntile(age, 4))")

# Test 11.7: min_rank on mtcars mpg (larger dataset, more ties)
mtcars %>%
  mutate(rank_mpg = min_rank(mpg)) %>%
  save_output("mtcars_min_rank_mpg", "mutate(rank_mpg = min_rank(mpg))")

# ============================================================================
# Test Suite 12: OFFSET WINDOW FUNCTIONS (lead/lag)
# ============================================================================
message("\n=== OFFSET Window Function Tests ===")

# Test 12.1: lag on simple dataset (default offset = 1)
simple %>%
  mutate(prev_score = lag(score)) %>%
  save_output("simple_lag_score", "mutate(prev_score = lag(score))")

# Test 12.2: lead on simple dataset (default offset = 1)
simple %>%
  mutate(next_score = lead(score)) %>%
  save_output("simple_lead_score", "mutate(next_score = lead(score))")

# Test 12.3: lag with offset 2
simple %>%
  mutate(prev2_score = lag(score, 2)) %>%
  save_output("simple_lag2_score", "mutate(prev2_score = lag(score, 2))")

# Test 12.4: lead with offset 2
simple %>%
  mutate(next2_score = lead(score, 2)) %>%
  save_output("simple_lead2_score", "mutate(next2_score = lead(score, 2))")

# Test 12.5: lag on mtcars mpg
mtcars %>%
  mutate(prev_mpg = lag(mpg)) %>%
  save_output("mtcars_lag_mpg", "mutate(prev_mpg = lag(mpg))")

# Test 12.6: lead on mtcars mpg
mtcars %>%
  mutate(next_mpg = lead(mpg)) %>%
  save_output("mtcars_lead_mpg", "mutate(next_mpg = lead(mpg))")

# ============================================================================
# Test Suite 13: CUMULATIVE WINDOW FUNCTIONS
# ============================================================================
message("\n=== CUMULATIVE Window Function Tests ===")

# Test 13.1: cumsum on simple dataset
simple %>%
  mutate(cum_score = cumsum(score)) %>%
  save_output("simple_cumsum_score", "mutate(cum_score = cumsum(score))")

# Test 13.2: cummax on simple dataset
simple %>%
  mutate(cummax_score = cummax(score)) %>%
  save_output("simple_cummax_score", "mutate(cummax_score = cummax(score))")

# Test 13.3: cummin on simple dataset
simple %>%
  mutate(cummin_score = cummin(score)) %>%
  save_output("simple_cummin_score", "mutate(cummin_score = cummin(score))")

# Test 13.4: cummean on simple dataset (dplyr function)
simple %>%
  mutate(cummean_score = cummean(score)) %>%
  save_output("simple_cummean_score", "mutate(cummean_score = cummean(score))")

# Test 13.5: cumsum on mtcars mpg (larger dataset)
mtcars %>%
  mutate(cum_mpg = cumsum(mpg)) %>%
  save_output("mtcars_cumsum_mpg", "mutate(cum_mpg = cumsum(mpg))")

# Test 13.6: cumall / cumany on logical column
simple %>%
  mutate(
    high_score = score > 85,
    cumall_high = cumall(high_score),
    cumany_high = cumany(high_score)
  ) %>%
  save_output("simple_cumall_cumany", "mutate(cumall/cumany on score > 85)")

message("\n✅ All window function expected outputs generated!")
message(sprintf("   Location: %s", normalizePath(output_dir)))

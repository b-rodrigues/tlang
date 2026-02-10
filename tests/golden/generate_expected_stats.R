#!/usr/bin/env Rscript

# Generate expected statistical outputs
# Linear models, correlations, etc.

library(dplyr)
library(readr)
library(broom)  # For tidy model outputs

data_dir <- "tests/golden/data"
output_dir <- "tests/golden/expected"

message("Generating expected statistical outputs...\n")

mtcars <- read_csv(file.path(data_dir, "mtcars.csv"), show_col_types = FALSE)

# ============================================================================
# Test Suite 8: LINEAR MODELS
# ============================================================================
message("=== LINEAR MODEL Tests ===")

# Test 8.1: Simple linear regression (mpg ~ hp) - coefficients (broom format)
lm_mpg_hp <- lm(mpg ~ hp, data = mtcars)
lm_mpg_hp_tidy <- tidy(lm_mpg_hp)
write_csv(lm_mpg_hp_tidy, file.path(output_dir, "lm_mpg_hp_coefficients.csv"))
message("✓ lm(mpg ~ hp) coefficients")

# Save model stats (full R stats)
lm_mpg_hp_stats <- tibble(
  r_squared = summary(lm_mpg_hp)$r.squared,
  adj_r_squared = summary(lm_mpg_hp)$adj.r.squared,
  sigma = summary(lm_mpg_hp)$sigma,
  df = summary(lm_mpg_hp)$df[2]
)
write_csv(lm_mpg_hp_stats, file.path(output_dir, "lm_mpg_hp_stats.csv"))
message("✓ lm(mpg ~ hp) statistics")

# Test 8.1b: Simple linear regression - T-compatible format
# T's lm() returns intercept, slope, r_squared
lm_mpg_hp_simple <- tibble(
  intercept = coef(lm_mpg_hp)[1],
  slope = coef(lm_mpg_hp)[2],
  r_squared = summary(lm_mpg_hp)$r.squared
)
write_csv(lm_mpg_hp_simple, file.path(output_dir, "lm_mpg_hp_simple.csv"))
message("✓ lm(mpg ~ hp) simple stats (T-compatible)")

# Test 8.2: Multiple regression (mpg ~ hp + wt)
lm_mpg_multi <- lm(mpg ~ hp + wt, data = mtcars)
lm_mpg_multi_tidy <- tidy(lm_mpg_multi)
write_csv(lm_mpg_multi_tidy, 
          file.path(output_dir, "lm_mpg_hp_wt_coefficients.csv"))
message("✓ lm(mpg ~ hp + wt) coefficients")

# Test 8.3: Linear model on iris (Sepal.Length ~ Petal.Length)
iris <- read_csv(file.path(data_dir, "iris.csv"), show_col_types = FALSE)
lm_iris <- lm(Sepal.Length ~ Petal.Length, data = iris)
lm_iris_tidy <- tidy(lm_iris)
write_csv(lm_iris_tidy, 
          file.path(output_dir, "lm_iris_sepal_petal_coefficients.csv"))
message("✓ lm(Sepal.Length ~ Petal.Length) coefficients")

# ============================================================================
# Test Suite 9: CORRELATIONS
# ============================================================================
message("\n=== CORRELATION Tests ===")

# Test 9.1: Simple correlation
cor_mpg_hp <- tibble(
  correlation = cor(mtcars$mpg, mtcars$hp)
)
write_csv(cor_mpg_hp, file.path(output_dir, "cor_mpg_hp.csv"))
message("✓ cor(mpg, hp)")

# Test 9.2: Correlation matrix
cor_matrix <- mtcars %>%
  select(mpg, hp, wt, qsec) %>%
  cor() %>%
  as.data.frame() %>%
  tibble::rownames_to_column("var1") %>%
  tidyr::pivot_longer(-var1, names_to = "var2", values_to = "correlation")
write_csv(cor_matrix, file.path(output_dir, "cor_matrix_mtcars.csv"))
message("✓ Correlation matrix (mpg, hp, wt, qsec)")

# Test 9.3: Correlation on iris
cor_iris <- tibble(
  correlation = cor(iris$Sepal.Length, iris$Petal.Length)
)
write_csv(cor_iris, file.path(output_dir, "cor_iris_sepal_petal.csv"))
message("✓ cor(Sepal.Length, Petal.Length)")

# ============================================================================
# Test Suite 10: DESCRIPTIVE STATISTICS
# ============================================================================
message("\n=== DESCRIPTIVE STATS Tests ===")

# Test 10.1: Summary statistics
summary_stats <- mtcars %>%
  summarize(
    mean_mpg = mean(mpg),
    sd_mpg = sd(mpg),
    median_mpg = median(mpg),
    min_mpg = min(mpg),
    max_mpg = max(mpg),
    q25_mpg = quantile(mpg, 0.25),
    q75_mpg = quantile(mpg, 0.75)
  )
write_csv(summary_stats, file.path(output_dir, "summary_stats_mpg.csv"))
message("✓ Summary statistics for mpg")

# Test 10.2: Quantiles
quantiles <- tibble(
  quantile = c(0, 0.25, 0.50, 0.75, 1.0),
  value = quantile(mtcars$mpg, c(0, 0.25, 0.50, 0.75, 1.0))
)
write_csv(quantiles, file.path(output_dir, "quantiles_mpg.csv"))
message("✓ Quantiles for mpg")

message("\n✅ All statistical outputs generated!")

#!/usr/bin/env Rscript
# tests/golden/generate_large_datasets.R
# Generate large test datasets for performance and correctness testing.
# Produces CSV files at 10k, 100k, and 1M row scales with diverse data types.

suppressPackageStartupMessages(library(dplyr))

set.seed(42)  # Reproducible generation

output_dir <- "tests/golden/data"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------
# Helper: write dataset with summary
# ---------------------------------------------------------------------------
write_dataset <- function(df, name) {
  path <- file.path(output_dir, paste0(name, ".csv"))
  write.csv(df, path, row.names = FALSE)
  cat(sprintf("  ✓ %s: %d rows x %d cols → %s\n",
              name, nrow(df), ncol(df), path))
}

# ---------------------------------------------------------------------------
# 10k rows, 10 columns (small dataset)
# ---------------------------------------------------------------------------
cat("Generating 10k-row dataset...\n")

n_10k <- 10000
df_10k <- data.frame(
  id         = seq_len(n_10k),
  name       = paste0("person_", seq_len(n_10k)),
  age        = sample(18:80, n_10k, replace = TRUE),
  salary     = round(runif(n_10k, 30000, 150000), 2),
  dept       = sample(c("eng", "sales", "hr", "ops", "finance"), n_10k, replace = TRUE),
  score      = round(rnorm(n_10k, mean = 75, sd = 12), 1),
  active     = sample(c(TRUE, FALSE), n_10k, replace = TRUE),
  region     = sample(c("north", "south", "east", "west"), n_10k, replace = TRUE),
  start_year = sample(2010:2024, n_10k, replace = TRUE),
  rating     = round(runif(n_10k, 1, 5), 1)
)

# Inject some NA values (~5% per column for select columns)
na_idx_age    <- sample(n_10k, round(n_10k * 0.05))
na_idx_salary <- sample(n_10k, round(n_10k * 0.05))
na_idx_score  <- sample(n_10k, round(n_10k * 0.05))
df_10k$age[na_idx_age]       <- NA
df_10k$salary[na_idx_salary] <- NA
df_10k$score[na_idx_score]   <- NA

write_dataset(df_10k, "large_10k")

# ---------------------------------------------------------------------------
# 100k rows, 15 columns (medium dataset)
# ---------------------------------------------------------------------------
cat("Generating 100k-row dataset...\n")

n_100k <- 100000
df_100k <- data.frame(
  id          = seq_len(n_100k),
  name        = paste0("user_", seq_len(n_100k)),
  age         = sample(18:80, n_100k, replace = TRUE),
  salary      = round(runif(n_100k, 25000, 200000), 2),
  dept        = sample(c("eng", "sales", "hr", "ops", "finance", "legal", "marketing"),
                       n_100k, replace = TRUE),
  score       = round(rnorm(n_100k, mean = 70, sd = 15), 1),
  active      = sample(c(TRUE, FALSE), n_100k, replace = TRUE),
  region      = sample(c("north", "south", "east", "west", "central"),
                       n_100k, replace = TRUE),
  start_year  = sample(2005:2024, n_100k, replace = TRUE),
  rating      = round(runif(n_100k, 1, 5), 1),
  bonus       = round(runif(n_100k, 0, 20000), 2),
  tenure      = sample(0:30, n_100k, replace = TRUE),
  level       = sample(c("junior", "mid", "senior", "lead", "director"),
                       n_100k, replace = TRUE),
  remote      = sample(c(TRUE, FALSE), n_100k, replace = TRUE),
  performance = sample(c("exceeds", "meets", "below"), n_100k,
                       replace = TRUE, prob = c(0.2, 0.6, 0.2))
)

# Inject NA values (~3% for select columns)
na_pct <- 0.03
for (col in c("age", "salary", "score", "bonus", "tenure")) {
  na_idx <- sample(n_100k, round(n_100k * na_pct))
  df_100k[[col]][na_idx] <- NA
}

write_dataset(df_100k, "large_100k")

# ---------------------------------------------------------------------------
# 1M rows, 20 columns (large dataset)
# ---------------------------------------------------------------------------
cat("Generating 1M-row dataset...\n")

n_1m <- 1000000
df_1m <- data.frame(
  id           = seq_len(n_1m),
  name         = paste0("record_", seq_len(n_1m)),
  value_a      = round(rnorm(n_1m, mean = 100, sd = 25), 2),
  value_b      = round(rnorm(n_1m, mean = 50, sd = 10), 2),
  value_c      = round(runif(n_1m, 0, 1000), 2),
  category     = sample(paste0("cat_", 1:50), n_1m, replace = TRUE),
  subcategory  = sample(paste0("sub_", 1:200), n_1m, replace = TRUE),
  flag_1       = sample(c(TRUE, FALSE), n_1m, replace = TRUE),
  flag_2       = sample(c(TRUE, FALSE), n_1m, replace = TRUE),
  region       = sample(c("NA", "EU", "APAC", "LATAM", "MEA"), n_1m, replace = TRUE),
  country      = sample(paste0("country_", 1:30), n_1m, replace = TRUE),
  date_year    = sample(2000:2025, n_1m, replace = TRUE),
  date_month   = sample(1:12, n_1m, replace = TRUE),
  amount       = round(runif(n_1m, 1, 10000), 2),
  quantity     = sample(1:100, n_1m, replace = TRUE),
  price        = round(runif(n_1m, 0.5, 500), 2),
  discount     = round(runif(n_1m, 0, 0.5), 2),
  score_x      = round(rnorm(n_1m, mean = 0, sd = 1), 4),
  score_y      = round(rnorm(n_1m, mean = 0, sd = 1), 4),
  weight       = round(runif(n_1m, 0.1, 10), 2)
)

# Inject NA values (~2% for select columns)
na_pct_1m <- 0.02
for (col in c("value_a", "value_b", "value_c", "amount", "score_x", "score_y")) {
  na_idx <- sample(n_1m, round(n_1m * na_pct_1m))
  df_1m[[col]][na_idx] <- NA
}

write_dataset(df_1m, "large_1m")

# ---------------------------------------------------------------------------
# Edge case datasets
# ---------------------------------------------------------------------------
cat("Generating edge case datasets...\n")

# All-NA column
df_all_na <- data.frame(
  id    = 1:100,
  group = sample(c("A", "B"), 100, replace = TRUE),
  value = rep(NA_real_, 100)
)
write_dataset(df_all_na, "edge_all_na_column")

# Single-value column (zero variance)
df_single_val <- data.frame(
  id    = 1:100,
  group = sample(c("A", "B", "C"), 100, replace = TRUE),
  value = rep(42, 100)
)
write_dataset(df_single_val, "edge_single_value")

# High cardinality groups (unique group per row)
df_high_card <- data.frame(
  id    = 1:1000,
  group = paste0("g_", 1:1000),
  value = rnorm(1000)
)
write_dataset(df_high_card, "edge_high_cardinality")

cat("\n✓ All large datasets generated successfully.\n")

#!/usr/bin/env Rscript

# Generate expected outputs using dplyr
# These are the "golden" results T should match

library(dplyr)
library(readr)

data_dir <- "tests/golden/data"
output_dir <- "tests/golden/expected"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Generating expected outputs from R/dplyr...\n")

# Helper to save with metadata
save_output <- function(df, name, operation) {
  filepath <- file.path(output_dir, paste0(name, ".csv"))
  write_csv(df, filepath)
  message(sprintf("✓ %s: %s (%d rows × %d cols)", 
                  operation, name, nrow(df), ncol(df)))
}

# ============================================================================
# Test Suite 1: SELECT operations (project columns)
# ============================================================================
message("=== SELECT Tests ===")

mtcars <- read_csv(file.path(data_dir, "mtcars.csv"), show_col_types = FALSE)

# Test 1.1: Select single column
mtcars %>%
  select(mpg) %>%
  save_output("mtcars_select_mpg", "select(mpg)")

# Test 1.2: Select multiple columns
mtcars %>%
  select(car_name, mpg, cyl, hp) %>%
  save_output("mtcars_select_multi", "select(car_name, mpg, cyl, hp)")

# Test 1.3: Select with reordering
mtcars %>%
  select(hp, mpg, car_name) %>%
  save_output("mtcars_select_reorder", "select(hp, mpg, car_name)")

# ============================================================================
# Test Suite 2: FILTER operations (row subsetting)
# ============================================================================
message("\n=== FILTER Tests ===")

# Test 2.1: Simple numeric filter
mtcars %>%
  filter(mpg > 20) %>%
  save_output("mtcars_filter_mpg_gt_20", "filter(mpg > 20)")

# Test 2.2: Multiple conditions (AND)
mtcars %>%
  filter(mpg > 20, cyl == 4) %>%
  save_output("mtcars_filter_mpg_and_cyl", "filter(mpg > 20, cyl == 4)")

# Test 2.3: OR condition
mtcars %>%
  filter(mpg > 30 | hp > 200) %>%
  save_output("mtcars_filter_mpg_or_hp", "filter(mpg > 30 | hp > 200)")

# Test 2.4: String equality
iris <- read_csv(file.path(data_dir, "iris.csv"), show_col_types = FALSE)
iris %>%
  filter(Species == "setosa") %>%
  save_output("iris_filter_setosa", "filter(Species == 'setosa')")

# ============================================================================
# Test Suite 3: MUTATE operations (column transformations)
# ============================================================================
message("\n=== MUTATE Tests ===")

# Test 3.1: Simple arithmetic
mtcars %>%
  mutate(mpg_double = mpg * 2) %>%
  save_output("mtcars_mutate_double", "mutate(mpg_double = mpg * 2)")

# Test 3.2: Multiple new columns
mtcars %>%
  mutate(
    hp_per_cyl = hp / cyl,
    efficient = mpg > 20
  ) %>%
  save_output("mtcars_mutate_multi", "mutate(hp_per_cyl, efficient)")

# Test 3.3: Overwrite existing column
mtcars %>%
  mutate(mpg = mpg * 1.5) %>%
  save_output("mtcars_mutate_overwrite", "mutate(mpg = mpg * 1.5)")

# Test 3.4: Column from multiple sources
mtcars %>%
  mutate(power_to_weight = hp / wt) %>%
  save_output("mtcars_mutate_ratio", "mutate(power_to_weight = hp / wt)")

# ============================================================================
# Test Suite 4: ARRANGE operations (sorting)
# ============================================================================
message("\n=== ARRANGE Tests ===")

# Test 4.1: Sort ascending
mtcars %>%
  arrange(mpg) %>%
  save_output("mtcars_arrange_mpg_asc", "arrange(mpg)")

# Test 4.2: Sort descending
mtcars %>%
  arrange(desc(mpg)) %>%
  save_output("mtcars_arrange_mpg_desc", "arrange(desc(mpg))")

# Test 4.3: Multi-column sort
mtcars %>%
  arrange(cyl, desc(mpg)) %>%
  save_output("mtcars_arrange_cyl_mpg", "arrange(cyl, desc(mpg))")

# ============================================================================
# Test Suite 5: GROUP_BY + SUMMARIZE operations
# ============================================================================
message("\n=== GROUP_BY + SUMMARIZE Tests ===")

# Test 5.1: Simple group by with mean
mtcars %>%
  group_by(cyl) %>%
  summarize(mean_mpg = mean(mpg)) %>%
  save_output("mtcars_groupby_cyl_mean_mpg", "group_by(cyl) %>% summarize(mean(mpg))")

# Test 5.2: Multiple aggregations
mtcars %>%
  group_by(cyl) %>%
  summarize(
    mean_mpg = mean(mpg),
    mean_hp = mean(hp),
    count = n()
  ) %>%
  save_output("mtcars_groupby_cyl_multi_agg", 
              "group_by(cyl) %>% summarize(mean_mpg, mean_hp, count)")

# Test 5.3: Group by multiple columns
mtcars %>%
  group_by(cyl, gear) %>%
  summarize(
    avg_mpg = mean(mpg),
    .groups = "drop"
  ) %>%
  save_output("mtcars_groupby_cyl_gear", 
              "group_by(cyl, gear) %>% summarize(avg_mpg)")

# Test 5.4: Various aggregation functions
mtcars %>%
  group_by(cyl) %>%
  summarize(
    min_mpg = min(mpg),
    max_mpg = max(mpg),
    sd_mpg = sd(mpg),
    count = n()
  ) %>%
  save_output("mtcars_groupby_various_aggs", 
              "group_by(cyl) %>% summarize(min, max, sd, n)")

# Test 5.5: Group by on iris dataset
iris %>%
  group_by(Species) %>%
  summarize(
    mean_petal_length = mean(Petal.Length),
    mean_petal_width = mean(Petal.Width)
  ) %>%
  save_output("iris_groupby_species", 
              "group_by(Species) %>% summarize(mean petal dims)")

# ============================================================================
# Test Suite 6: CHAINED OPERATIONS (pipelines)
# ============================================================================
message("\n=== PIPELINE Tests ===")

# Test 6.1: filter %>% select
mtcars %>%
  filter(mpg > 20) %>%
  select(car_name, mpg, cyl) %>%
  save_output("mtcars_pipeline_filter_select", 
              "filter(mpg > 20) %>% select(...)")

# Test 6.2: select %>% filter %>% arrange
mtcars %>%
  select(car_name, mpg, hp) %>%
  filter(hp > 100) %>%
  arrange(desc(mpg)) %>%
  save_output("mtcars_pipeline_select_filter_arrange", 
              "select %>% filter %>% arrange")

# Test 6.3: filter %>% mutate %>% arrange
mtcars %>%
  filter(cyl == 6) %>%
  mutate(efficiency = mpg / hp * 1000) %>%
  arrange(desc(efficiency)) %>%
  save_output("mtcars_pipeline_filter_mutate_arrange", 
              "filter %>% mutate %>% arrange")

# Test 6.4: group_by %>% mutate (window function)
mtcars %>%
  group_by(cyl) %>%
  mutate(mpg_vs_cyl_avg = mpg - mean(mpg)) %>%
  ungroup() %>%
  save_output("mtcars_pipeline_groupby_mutate", 
              "group_by %>% mutate (window)")

# Test 6.5: Complex pipeline
iris %>%
  filter(Petal.Length > 1.5) %>%
  mutate(petal_area = Petal.Length * Petal.Width) %>%
  group_by(Species) %>%
  summarize(
    mean_area = mean(petal_area),
    count = n(),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_area)) %>%
  save_output("iris_pipeline_complex", 
              "Complex pipeline: filter %>% mutate %>% group_by %>% summarize %>% arrange")

# ============================================================================
# Test Suite 7: NA HANDLING
# ============================================================================
message("\n=== NA HANDLING Tests ===")

data_with_nas <- read_csv(file.path(data_dir, "data_with_nas.csv"), 
                       show_col_types = FALSE)

# Test 7.1: Mean with na.rm
data_with_nas %>%
  summarize(
    mean_ozone = mean(Ozone, na.rm = TRUE),
    mean_solar = mean(Solar.R, na.rm = TRUE)
  ) %>%
  save_output("airquality_mean_na_rm", "summarize with na.rm=TRUE")

# Test 7.2: Filter out NAs
data_with_nas %>%
  filter(!is.na(Ozone)) %>%
  save_output("airquality_filter_no_na", "filter(!is.na(Ozone))")

# Test 7.3: Group by with NAs
data_with_nas %>%
  mutate(temp_category = ifelse(Temp > 75, "hot", "cool")) %>%
  group_by(temp_category) %>%
  summarize(
    mean_ozone = mean(Ozone, na.rm = TRUE),
    count = n(),
    .groups = "drop"
  ) %>%
  save_output("airquality_groupby_with_nas", "group_by with NAs present")

message("\n✅ All expected outputs generated!")
message(sprintf("   Location: %s", normalizePath(output_dir)))
message(sprintf("   Total files: %d", 
                length(list.files(output_dir, pattern = "*.csv"))))

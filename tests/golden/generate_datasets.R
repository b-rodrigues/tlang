#!/usr/bin/env Rscript

# Generate test datasets from R's built-in data
# Export as CSV for T to read

library(dplyr)
library(readr)

output_dir <- "tests/golden/data"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Generating test datasets...")

# 1. mtcars - Motor Trend Car Road Tests
data(mtcars)
mtcars_with_names <- mtcars %>%
  tibble::rownames_to_column("car_name")
write_csv(mtcars_with_names, file.path(output_dir, "mtcars.csv"))
message("✓ Exported mtcars.csv (32 rows × 12 cols)")

# 2. iris - Edgar Anderson's Iris Data
data(iris)
write_csv(iris, file.path(output_dir, "iris.csv"))
message("✓ Exported iris.csv (150 rows × 5 cols)")

# 3. airquality - New York Air Quality Measurements
data(airquality)
write_csv(airquality, file.path(output_dir, "airquality.csv"))
message("✓ Exported airquality.csv (153 rows × 6 cols)")

# 4. ChickWeight - Weight vs Age of Chicks
data(ChickWeight)
write_csv(ChickWeight, file.path(output_dir, "chickweight.csv"))
message("✓ Exported chickweight.csv (578 rows × 4 cols)")

# 5. ToothGrowth - Effect of Vitamin C on Tooth Growth
data(ToothGrowth)
write_csv(ToothGrowth, file.path(output_dir, "toothgrowth.csv"))
message("✓ Exported toothgrowth.csv (60 rows × 3 cols)")

# 6. Create a dataset with NAs for NA handling tests
airquality_subset <- airquality %>%
  select(Ozone, Solar.R, Wind, Temp) %>%
  head(50)
write_csv(airquality_subset, file.path(output_dir, "data_with_nas.csv"))
message("✓ Exported data_with_nas.csv (50 rows × 4 cols, contains NAs)")

# 7. Create a small dataset for exact comparison
simple_data <- tibble(
  id = 1:10,
  name = c("Alice", "Bob", "Charlie", "David", "Eve", 
           "Frank", "Grace", "Henry", "Iris", "Jack"),
  age = c(25, 30, 35, 28, 22, 45, 33, 29, 31, 27),
  score = c(85.5, 92.3, 78.9, 88.1, 95.0, 
            82.4, 90.2, 76.5, 89.3, 91.7),
  passed = c(TRUE, TRUE, TRUE, TRUE, TRUE, 
             TRUE, TRUE, TRUE, TRUE, TRUE)
)
write_csv(simple_data, file.path(output_dir, "simple.csv"))
message("✓ Exported simple.csv (10 rows × 5 cols)")

# 8. Edge case: Empty DataFrame
empty_data <- tibble(
  col1 = numeric(0),
  col2 = character(0),
  col3 = logical(0)
)
write_csv(empty_data, file.path(output_dir, "empty.csv"))
message("✓ Exported empty.csv (0 rows × 3 cols)")

# 9. Edge case: Single row DataFrame
single_row <- tibble(
  id = 1,
  value = 42.0,
  label = "single"
)
write_csv(single_row, file.path(output_dir, "single_row.csv"))
message("✓ Exported single_row.csv (1 row × 3 cols)")

# 10. Edge case: Division by zero and special values
special_values <- tibble(
  id = 1:6,
  value = c(1.0, 0.0, -1.0, 10.0, 100.0, 5.0),
  divisor = c(2.0, 1.0, 0.0, 0.0, 10.0, 0.0)
)
write_csv(special_values, file.path(output_dir, "special_values.csv"))
message("✓ Exported special_values.csv (6 rows × 3 cols)")

message("\n✅ All datasets generated successfully!")
message(sprintf("   Location: %s", normalizePath(output_dir)))

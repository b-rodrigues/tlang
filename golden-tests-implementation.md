# Golden Testing Implementation Plan: T vs R Comparison

## **Overview**

Create a comprehensive golden testing framework where T's colcraft and stats operations are compared against R's dplyr and stats packages. This serves as:
1. **Specification**: R defines the expected behavior
2. **Regression Testing**: Ensures T matches R's output
3. **TDD Framework**: Tests exist before features are implemented

---

## **Phase 1: Nix Configuration for R (Week 1, Day 1-2)**

### **1.1: Update flake.nix to Include R**

#### **Add R with Packages**

```nix
# flake.nix
{
  description = "T language development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Add rstats-on-nix for latest R packages
    rstats-on-nix.url = "github:rstats-on-nix/nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, rstats-on-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };

        # R packages from rstats-on-nix
        r-pkgs = rstats-on-nix.packages.${system};
        
        # Build R with specific packages
        R-with-packages = pkgs.rWrapper.override {
          packages = with r-pkgs; [
            dplyr
            readr
            testthat
            stringr
            tidyr
            purrr
            # Add more as needed
          ];
        };

        ocamlVersion = pkgs.ocaml-ng.ocamlPackages_5_2;

      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            # OCaml toolchain
            ocamlVersion.ocaml
            ocamlVersion.dune_3
            ocamlVersion.findlib
            ocamlVersion.menhir
            ocamlVersion.menhirLib
            ocamlVersion.utop
            ocamlVersion.merlin
            ocamlVersion.ocaml-lsp
            ocamlVersion.ocamlformat
            
            # C dependencies
            pkgs.pkg-config
            pkgs.arrow-glib
            pkgs.glib
            pkgs.gsl
            
            # R environment
            R-with-packages
            
            # Testing & utilities
            pkgs.valgrind
            pkgs.git
          ];

          shellHook = ''
            echo "T development environment loaded"
            echo "OCaml: $(ocaml --version)"
            echo "R: $(R --version | head -n1)"
            echo ""
            echo "Available commands:"
            echo "  dune build    - Build T"
            echo "  dune test     - Run OCaml tests"
            echo "  make golden   - Run golden tests (T vs R)"
            echo "  R             - Launch R console"
          '';
        };
      }
    );

  # Configure cachix for R packages
  nixConfig = {
    extra-substituters = [
      "https://rstats-on-nix.cachix.org"
    ];
    extra-trusted-public-keys = [
      "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
    ];
  };
}
```

#### **Checklist:**
- [ ] Update flake.nix with rstats-on-nix input
- [ ] Add R-with-packages derivation
- [ ] Configure nixConfig for cachix
- [ ] Test: `nix develop` should provide R
- [ ] Verify: `R --version` works in dev shell
- [ ] Verify: `R -e "library(dplyr)"` succeeds

---

## **Phase 2: Test Data Generation (Week 1, Day 3)**

### **2.1: Create R Script to Export Test Datasets**

#### **File: tests/golden/generate_datasets.R**

```r
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

message("\n✅ All datasets generated successfully!")
message(sprintf("   Location: %s", normalizePath(output_dir)))
```

#### **Checklist:**
- [ ] Create tests/golden/data/ directory
- [ ] Create generate_datasets.R script
- [ ] Make executable: `chmod +x tests/golden/generate_datasets.R`
- [ ] Run: `Rscript tests/golden/generate_datasets.R`
- [ ] Verify 7 CSV files exist in tests/golden/data/
- [ ] Add to .gitignore: `tests/golden/data/*.csv` (generated files)
- [ ] Add to Git: `tests/golden/generate_datasets.R` (source script)

---

## **Phase 3: R Golden Outputs (Week 1, Day 4-5)**

### **3.1: Generate Expected Outputs from dplyr**

#### **File: tests/golden/generate_expected.R**

```r
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

airquality <- read_csv(file.path(data_dir, "data_with_nas.csv"), 
                       show_col_types = FALSE)

# Test 7.1: Mean with na.rm
airquality %>%
  summarize(
    mean_ozone = mean(Ozone, na.rm = TRUE),
    mean_solar = mean(Solar.R, na.rm = TRUE)
  ) %>%
  save_output("airquality_mean_na_rm", "summarize with na.rm=TRUE")

# Test 7.2: Filter out NAs
airquality %>%
  filter(!is.na(Ozone)) %>%
  save_output("airquality_filter_no_na", "filter(!is.na(Ozone))")

# Test 7.3: Group by with NAs
airquality %>%
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
```

#### **Checklist:**
- [ ] Create tests/golden/expected/ directory
- [ ] Create generate_expected.R script
- [ ] Make executable: `chmod +x tests/golden/generate_expected.R`
- [ ] Run: `Rscript tests/golden/generate_expected.R`
- [ ] Verify ~30+ CSV files in tests/golden/expected/
- [ ] Add to .gitignore: `tests/golden/expected/*.csv`
- [ ] Add to Git: `tests/golden/generate_expected.R`

---

### **3.2: Generate Expected Stats Outputs**

#### **File: tests/golden/generate_expected_stats.R**

```r
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

# Test 8.1: Simple linear regression (mpg ~ hp)
lm_mpg_hp <- lm(mpg ~ hp, data = mtcars)
lm_mpg_hp_tidy <- tidy(lm_mpg_hp)
write_csv(lm_mpg_hp_tidy, file.path(output_dir, "lm_mpg_hp_coefficients.csv"))
message("✓ lm(mpg ~ hp) coefficients")

# Save model stats
lm_mpg_hp_stats <- tibble(
  r_squared = summary(lm_mpg_hp)$r.squared,
  adj_r_squared = summary(lm_mpg_hp)$adj.r.squared,
  sigma = summary(lm_mpg_hp)$sigma,
  df = summary(lm_mpg_hp)$df[2]
)
write_csv(lm_mpg_hp_stats, file.path(output_dir, "lm_mpg_hp_stats.csv"))
message("✓ lm(mpg ~ hp) statistics")

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
```

#### **Checklist:**
- [ ] Create generate_expected_stats.R
- [ ] Add broom package to flake.nix R packages
- [ ] Run: `Rscript tests/golden/generate_expected_stats.R`
- [ ] Verify stats outputs in tests/golden/expected/

---

## **Phase 4: T Test Scripts (Week 2, Day 1-3)**

### **4.1: Create T Test Runner**

#### **File: tests/golden/run_t_tests.sh**

```bash
#!/usr/bin/env bash

# Run T operations and save outputs for comparison with R

set -e

T_REPL="dune exec src/repl.exe --"
DATA_DIR="tests/golden/data"
OUTPUT_DIR="tests/golden/t_outputs"

mkdir -p "$OUTPUT_DIR"

echo "=== Running T Golden Tests ==="
echo ""

run_t_test() {
  local test_name="$1"
  local t_script="$2"
  local output_file="$OUTPUT_DIR/${test_name}.csv"
  
  echo "Running: $test_name"
  echo "$t_script" | $T_REPL > "$output_file" 2>&1 || {
    echo "  ❌ FAILED: $test_name"
    return 1
  }
  echo "  ✓ Output saved to $output_file"
}

# ============================================================================
# Test Suite 1: SELECT
# ============================================================================
echo "=== SELECT Tests ==="

run_t_test "mtcars_select_mpg" "
df = read_csv(\"$DATA_DIR/mtcars.csv\")
result = df |> select(\"mpg\")
result
"

run_t_test "mtcars_select_multi" "
df = read_csv(\"$DATA_DIR/mtcars.csv\")
result = df |> select(\"car_name\", \"mpg\", \"cyl\", \"hp\")
result
"

# ... more select tests ...

# ============================================================================
# Test Suite 2: FILTER
# ============================================================================
echo ""
echo "=== FILTER Tests ==="

run_t_test "mtcars_filter_mpg_gt_20" "
df = read_csv(\"$DATA_DIR/mtcars.csv\")
result = df |> filter(mpg > 20.0)
result
"

# ... more filter tests ...

# ============================================================================
# Test Suite 5: GROUP_BY + SUMMARIZE
# ============================================================================
echo ""
echo "=== GROUP_BY + SUMMARIZE Tests ==="

run_t_test "mtcars_groupby_cyl_mean_mpg" "
df = read_csv(\"$DATA_DIR/mtcars.csv\")
result = df |> group_by(\"cyl\") |> summarize(mean_mpg = mean(mpg))
result
"

# ... more groupby tests ...

echo ""
echo "✅ All T tests completed!"
echo "   Outputs in: $OUTPUT_DIR"
```

#### **Better Approach: Individual T Script Files**

Create individual `.t` files for each test case:

#### **File: tests/golden/t_scripts/select_mpg.t**

```t
-- Test: Select single column (mpg)
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> select("mpg")
write_csv(result, "tests/golden/t_outputs/mtcars_select_mpg.csv")
print("✓ select(mpg) complete")
```

#### **File: tests/golden/t_scripts/filter_mpg_gt_20.t**

```t
-- Test: Filter mpg > 20
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> filter(mpg > 20.0)
write_csv(result, "tests/golden/t_outputs/mtcars_filter_mpg_gt_20.csv")
print("✓ filter(mpg > 20) complete")
```

#### **File: tests/golden/run_all_t_tests.sh**

```bash
#!/usr/bin/env bash

set -e

T_REPL="dune exec src/repl.exe --"
SCRIPT_DIR="tests/golden/t_scripts"
OUTPUT_DIR="tests/golden/t_outputs"

mkdir -p "$OUTPUT_DIR"

echo "=== Running All T Golden Tests ==="
echo ""

passed=0
failed=0

for script in "$SCRIPT_DIR"/*.t; do
  test_name=$(basename "$script" .t)
  echo -n "Running: $test_name ... "
  
  if $T_REPL run "$script" > /dev/null 2>&1; then
    echo "✓"
    ((passed++))
  else
    echo "❌ FAILED"
    ((failed++))
  fi
done

echo ""
echo "=== Results ==="
echo "  Passed: $passed"
echo "  Failed: $failed"

if [ $failed -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed"
  exit 1
fi
```

#### **Checklist:**
- [ ] Create tests/golden/t_scripts/ directory
- [ ] Create .t script for each test case (30+ scripts)
- [ ] Create run_all_t_tests.sh
- [ ] Make executable: `chmod +x tests/golden/run_all_t_tests.sh`
- [ ] Test: `./tests/golden/run_all_t_tests.sh`
- [ ] Add to .gitignore: `tests/golden/t_outputs/*.csv`
- [ ] Add to Git: `tests/golden/t_scripts/*.t`

---

## **Phase 5: R Comparison Tests with testthat (Week 2, Day 4-5)**

### **5.1: Create testthat Comparison Suite**

#### **File: tests/golden/test_golden.R**

```r
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
  skip("Window functions not yet implemented in T")
  compare_csvs("mtcars_pipeline_groupby_mutate")
})

test_that("PIPELINE: complex iris pipeline", {
  compare_csvs("iris_pipeline_complex")
})

# ============================================================================
# Test Suite 7: NA HANDLING
# ============================================================================

test_that("NA: mean with na.rm", {
  skip("NA handling not yet implemented in T")
  compare_csvs("airquality_mean_na_rm")
})

test_that("NA: filter out NAs", {
  skip("NA handling not yet implemented in T")
  compare_csvs("airquality_filter_no_na")
})

# ============================================================================
# Test Suite 8: LINEAR MODELS
# ============================================================================

test_that("LM: simple regression coefficients", {
  skip("lm() not yet implemented in T")
  compare_csvs("lm_mpg_hp_coefficients", tolerance = 1e-5)
})

test_that("LM: simple regression statistics", {
  skip("lm() not yet implemented in T")
  compare_csvs("lm_mpg_hp_stats", tolerance = 1e-5)
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
# SUMMARY REPORT
# ============================================================================

message("\n" , "=".repeat(70))
message("GOLDEN TEST SUMMARY")
message("=".repeat(70))

# Get test results
results <- as.data.frame(testthat::get_reporter()$.results)
if (nrow(results) > 0) {
  passed <- sum(results$passed, na.rm = TRUE)
  failed <- sum(results$failed, na.rm = TRUE)
  skipped <- sum(results$skipped, na.rm = TRUE)
  
  message(sprintf("Passed:  %d", passed))
  message(sprintf("Failed:  %d", failed))
  message(sprintf("Skipped: %d (not yet implemented)", skipped))
  message("=".repeat(70))
  
  if (failed == 0) {
    message("✅ ALL IMPLEMENTED TESTS PASSED!")
  } else {
    message("❌ SOME TESTS FAILED")
  }
} else {
  message("No results available")
}
```

#### **Checklist:**
- [ ] Create test_golden.R
- [ ] Add testthat to flake.nix R packages
- [ ] Test manually: `Rscript tests/golden/test_golden.R`
- [ ] Verify it runs and reports results
- [ ] Add skip() for unimplemented features

---

## **Phase 6: Makefile Integration (Week 3, Day 1)**

### **6.1: Create Makefile Targets**

#### **File: Makefile**

```makefile
.PHONY: golden golden-setup golden-data golden-expected golden-run golden-compare golden-clean

# Main golden test target
golden: golden-setup golden-data golden-expected golden-run golden-compare

# Setup: ensure directories exist
golden-setup:
	@echo "=== Setting up golden test directories ==="
	@mkdir -p tests/golden/data
	@mkdir -p tests/golden/expected
	@mkdir -p tests/golden/t_outputs
	@mkdir -p tests/golden/t_scripts

# Generate test data (R datasets -> CSV)
golden-data:
	@echo "=== Generating test datasets ==="
	@Rscript tests/golden/generate_datasets.R

# Generate expected outputs (R/dplyr -> CSV)
golden-expected:
	@echo "=== Generating expected outputs from R ==="
	@Rscript tests/golden/generate_expected.R
	@Rscript tests/golden/generate_expected_stats.R

# Run T tests (T -> CSV)
golden-run:
	@echo "=== Running T test scripts ==="
	@./tests/golden/run_all_t_tests.sh

# Compare T outputs vs R expected (testthat)
golden-compare:
	@echo "=== Comparing T outputs vs R expected ==="
	@Rscript tests/golden/test_golden.R

# Clean generated files
golden-clean:
	@echo "=== Cleaning golden test outputs ==="
	@rm -rf tests/golden/data/*.csv
	@rm -rf tests/golden/expected/*.csv
	@rm -rf tests/golden/t_outputs/*.csv
	@echo "✓ Cleaned"

# Quick check (assumes data and expected already generated)
golden-quick: golden-run golden-compare
```

#### **Checklist:**
- [ ] Add golden targets to Makefile
- [ ] Test: `make golden-setup`
- [ ] Test: `make golden-data`
- [ ] Test: `make golden-expected`
- [ ] Test: `make golden-run`
- [ ] Test: `make golden-compare`
- [ ] Test: `make golden` (full pipeline)

---

## **Phase 7: CI Integration (Week 3, Day 2-3)**

### **7.1: GitHub Actions Workflow**

#### **File: .github/workflows/golden-tests.yml**

```yaml
name: Golden Tests (T vs R)

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  golden-tests:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4
    
    - name: Install Nix
      uses: cachix/install-nix-action@v24
      with:
        nix_path: nixpkgs=channel:nixos-unstable
        extra_nix_config: |
          experimental-features = nix-command flakes
          substituters = https://cache.nixos.org https://rstats-on-nix.cachix.org
          trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0=
    
    - name: Setup Cachix (for R packages)
      uses: cachix/cachix-action@v13
      with:
        name: rstats-on-nix
        authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
        skipPush: true
    
    - name: Build T
      run: nix develop --command dune build
    
    - name: Generate test data (R datasets)
      run: nix develop --command make golden-data
    
    - name: Generate expected outputs (R/dplyr)
      run: nix develop --command make golden-expected
    
    - name: Run T test scripts
      run: nix develop --command make golden-run
      continue-on-error: true
    
    - name: Compare outputs (testthat)
      run: nix develop --command make golden-compare
      continue-on-error: true
    
    - name: Upload test results
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: golden-test-outputs
        path: |
          tests/golden/t_outputs/
          tests/golden/expected/
        retention-days: 7
    
    - name: Upload test report
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: golden-test-report
        path: tests/golden/test_results.xml
        retention-days: 30

  # Optional: Generate coverage report
  coverage:
    runs-on: ubuntu-latest
    needs: golden-tests
    
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4
    
    - name: Install Nix
      uses: cachix/install-nix-action@v24
    
    - name: Generate coverage report
      run: |
        nix develop --command bash -c '
          Rscript tests/golden/generate_coverage_report.R
        '
    
    - name: Upload coverage
      uses: actions/upload-artifact@v4
      with:
        name: test-coverage-report
        path: tests/golden/coverage_report.html
```

#### **Checklist:**
- [ ] Create .github/workflows/golden-tests.yml
- [ ] Configure Cachix secrets in GitHub repo settings
- [ ] Test workflow on a branch
- [ ] Verify artifacts are uploaded
- [ ] Add badge to README.md

---

### **7.2: Coverage Tracking Script**

#### **File: tests/golden/generate_coverage_report.R**

```r
#!/usr/bin/env Rscript

# Generate a coverage report: which tests pass, which are skipped

library(dplyr)
library(readr)

expected_dir <- "tests/golden/expected"
t_output_dir <- "tests/golden/t_outputs"

expected_files <- list.files(expected_dir, pattern = "*.csv")
t_output_files <- list.files(t_output_dir, pattern = "*.csv")

coverage <- tibble(
  test_name = gsub(".csv$", "", expected_files)
) %>%
  mutate(
    has_t_output = test_name %in% gsub(".csv$", "", t_output_files),
    status = ifelse(has_t_output, "IMPLEMENTED", "NOT IMPLEMENTED")
  ) %>%
  arrange(status, test_name)

# Count stats
total_tests <- nrow(coverage)
implemented <- sum(coverage$has_t_output)
not_implemented <- total_tests - implemented
coverage_pct <- round(100 * implemented / total_tests, 1)

# Print summary
message("=== Golden Test Coverage ===")
message(sprintf("Total tests:        %d", total_tests))
message(sprintf("Implemented:        %d", implemented))
message(sprintf("Not implemented:    %d", not_implemented))
message(sprintf("Coverage:           %.1f%%", coverage_pct))

# Generate HTML report
html_output <- sprintf('
<!DOCTYPE html>
<html>
<head>
  <title>T Golden Test Coverage Report</title>
  <style>
    body { font-family: sans-serif; margin: 40px; }
    h1 { color: #333; }
    .summary { background: #f0f0f0; padding: 20px; border-radius: 5px; margin: 20px 0; }
    .progress { background: #ddd; height: 30px; border-radius: 5px; overflow: hidden; }
    .progress-bar { background: #4CAF50; height: 100%%; line-height: 30px; color: white; text-align: center; }
    table { border-collapse: collapse; width: 100%%; margin-top: 20px; }
    th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
    th { background-color: #4CAF50; color: white; }
    tr:nth-child(even) { background-color: #f2f2f2; }
    .implemented { color: green; font-weight: bold; }
    .not-implemented { color: red; }
  </style>
</head>
<body>
  <h1>T Golden Test Coverage Report</h1>
  
  <div class="summary">
    <h2>Summary</h2>
    <p>Total tests: <strong>%d</strong></p>
    <p>Implemented: <strong>%d</strong> (%.1f%%)</p>
    <p>Not implemented: <strong>%d</strong></p>
    
    <div class="progress">
      <div class="progress-bar" style="width: %.1f%%">%.1f%% Complete</div>
    </div>
  </div>
  
  <h2>Test Details</h2>
  <table>
    <thead>
      <tr>
        <th>Test Name</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
', total_tests, implemented, coverage_pct, not_implemented, coverage_pct, coverage_pct)

for (i in 1:nrow(coverage)) {
  row <- coverage[i, ]
  status_class <- ifelse(row$has_t_output, "implemented", "not-implemented")
  html_output <- paste0(html_output, sprintf('
      <tr>
        <td>%s</td>
        <td class="%s">%s</td>
      </tr>
', row$test_name, status_class, row$status))
}

html_output <- paste0(html_output, '
    </tbody>
  </table>
  
  <p style="margin-top: 40px; color: #666;">
    Generated: ', Sys.time(), '
  </p>
</body>
</html>
')

# Write HTML report
writeLines(html_output, "tests/golden/coverage_report.html")
message("\n✓ Coverage report generated: tests/golden/coverage_report.html")

# Write CSV for CI
write_csv(coverage, "tests/golden/coverage.csv")
```

#### **Checklist:**
- [ ] Create generate_coverage_report.R
- [ ] Run manually: `Rscript tests/golden/generate_coverage_report.R`
- [ ] Open coverage_report.html in browser
- [ ] Verify it shows test status
- [ ] Add to CI workflow

---

## **Phase 8: Comprehensive Test Cases (Week 3, Day 4-5)**

### **8.1: Complete Test Matrix**

Create **ALL** test cases as `.t` scripts. Here's the full list to implement:

#### **SELECT Tests (tests/golden/t_scripts/)**
```
select_mpg.t
select_multi.t
select_reorder.t
```

#### **FILTER Tests**
```
filter_mpg_gt_20.t
filter_mpg_and_cyl.t
filter_mpg_or_hp.t
filter_iris_setosa.t
filter_numeric_eq.t
filter_numeric_gte.t
filter_string_contains.t (if implemented)
```

#### **MUTATE Tests**
```
mutate_double.t
mutate_multi.t
mutate_overwrite.t
mutate_ratio.t
mutate_boolean.t
mutate_string_concat.t (if implemented)
```

#### **ARRANGE Tests**
```
arrange_mpg_asc.t
arrange_mpg_desc.t
arrange_cyl_mpg.t
arrange_multi_desc.t
```

#### **GROUP_BY + SUMMARIZE Tests**
```
groupby_cyl_mean_mpg.t
groupby_cyl_multi_agg.t
groupby_cyl_gear.t
groupby_various_aggs.t
groupby_iris_species.t
```

#### **PIPELINE Tests**
```
pipeline_filter_select.t
pipeline_select_filter_arrange.t
pipeline_filter_mutate_arrange.t
pipeline_groupby_mutate.t (window function - TDD)
pipeline_iris_complex.t
```

#### **NA HANDLING Tests (TDD - not yet implemented)**
```
na_mean_rm.t
na_filter.t
na_groupby.t
```

#### **STATS Tests**
```
lm_mpg_hp.t (TDD)
lm_mpg_hp_wt.t (TDD)
lm_iris_sepal_petal.t (TDD)
cor_mpg_hp.t
cor_matrix.t
cor_iris.t
summary_stats_mpg.t
quantiles_mpg.t
```

#### **Checklist:**
- [ ] Create 40+ .t test scripts
- [ ] Each script loads data, performs operation, writes CSV
- [ ] Use skip() in test_golden.R for unimplemented features
- [ ] Document expected behavior in comments

---

## **Phase 9: Documentation & Maintenance (Week 4)**

### **9.1: README Documentation**

#### **File: tests/golden/README.md**

```markdown
# Golden Testing Framework: T vs R

This directory contains the golden testing framework that compares T's output
against R's dplyr and stats packages to ensure correctness and compatibility.

## Overview

The testing workflow:

1. **Generate Test Data**: R exports built-in datasets (mtcars, iris, etc.) to CSV
2. **Generate Expected Outputs**: R/dplyr runs operations and saves results
3. **Run T Tests**: T runs the same operations and saves outputs
4. **Compare**: testthat compares T outputs vs R expected outputs

## Directory Structure

```
tests/golden/
├── README.md                    # This file
├── generate_datasets.R          # Export R datasets to CSV
├── generate_expected.R          # Generate expected outputs (dplyr)
├── generate_expected_stats.R    # Generate expected outputs (stats)
├── test_golden.R                # testthat comparison suite
├── run_all_t_tests.sh           # Run all T test scripts
├── generate_coverage_report.R   # Generate coverage HTML report
├── data/                        # Generated CSV datasets (gitignored)
├── expected/                    # Expected outputs from R (gitignored)
├── t_outputs/                   # T outputs for comparison (gitignored)
└── t_scripts/                   # T test scripts (.t files)
    ├── select_mpg.t
    ├── filter_mpg_gt_20.t
    ├── groupby_cyl_mean_mpg.t
    └── ... (40+ test scripts)
```

## Running Tests

### Full Test Suite

```bash
make golden
```

This runs the entire pipeline:
1. Generates test data
2. Generates expected outputs
3. Runs T tests
4. Compares outputs

### Quick Test (assumes data already generated)

```bash
make golden-quick
```

### Individual Steps

```bash
make golden-data       # Generate datasets
make golden-expected   # Generate R expected outputs
make golden-run        # Run T tests
make golden-compare    # Compare outputs
```

### Clean Generated Files

```bash
make golden-clean
```

## Test Coverage

View current test coverage:

```bash
Rscript tests/golden/generate_coverage_report.R
open tests/golden/coverage_report.html
```

## Adding New Tests

### 1. Add Expected Output (R)

Edit `generate_expected.R`:

```r
mtcars %>%
  your_new_operation() %>%
  save_output("test_name", "Description")
```

### 2. Add T Test Script

Create `t_scripts/test_name.t`:

```t
-- Test: Your new operation
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> your_new_operation()
write_csv(result, "tests/golden/t_outputs/test_name.csv")
```

### 3. Add testthat Assertion

Edit `test_golden.R`:

```r
test_that("Your new operation", {
  compare_csvs("test_name")
})
```

### 4. Run Tests

```bash
make golden
```

## Test-Driven Development (TDD)

For **unimplemented features**, tests are marked with `skip()`:

```r
test_that("Window functions", {
  skip("Window functions not yet implemented in T")
  compare_csvs("pipeline_groupby_mutate")
})
```

This allows you to:
- Define expected behavior upfront
- Track implementation progress
- Ensure correctness when features are added

## CI Integration

Golden tests run automatically on:
- Every push to main/develop
- Every pull request

See: `.github/workflows/golden-tests.yml`

## Interpreting Results

### All Passed ✅
```
Passed:  30
Failed:  0
Skipped: 10 (not yet implemented)

✅ ALL IMPLEMENTED TESTS PASSED!
```

### Some Failed ❌
```
Passed:  25
Failed:  5
Skipped: 10

❌ SOME TESTS FAILED

Check the error messages for details.
```

Common failure reasons:
- Floating point precision differences (adjust tolerance)
- Column order differences (use `sort(names(...))`)
- Missing features in T (add `skip()` until implemented)

## Troubleshooting

### R packages not found

```bash
nix develop
R -e "library(dplyr)"
```

If it fails, check flake.nix includes the package.

### T test fails to run

```bash
dune build
dune exec src/repl.exe -- run t_scripts/test_name.t
```

Check for syntax errors or missing features.

### Tolerance issues

For numerical comparisons, adjust tolerance in `compare_csvs()`:

```r
compare_csvs("test_name", tolerance = 1e-5)  # More lenient
```

## Metrics

Current test coverage: **See `coverage_report.html`**

Target: **80% coverage** before Beta release


#### **Checklist:**
- [ ] Create tests/golden/README.md
- [ ] Document all commands
- [ ] Add troubleshooting section
- [ ] Link from main README.md

---

### **9.2: Update Main README**

#### **Add to main README.md:**

````markdown
## Testing

T uses a comprehensive golden testing framework that compares outputs against
R's dplyr and stats packages.

### Run All Tests

```bash
make test         # OCaml unit tests
make golden       # Golden tests (T vs R)
```

### Test Coverage

Current coverage: [![Coverage](https://img.shields.io/badge/coverage-75%25-yellow)](tests/golden/coverage_report.html)

See [Golden Testing Documentation](tests/golden/README.md) for details.
````

---

## **Phase 10: Advanced Test Cases (Optional - Week 5+)**

### **10.1: Edge Cases**

Add tests for:
- Empty DataFrames
- Single row DataFrames
- Very large DataFrames (performance)
- Type coercion edge cases
- Division by zero
- Inf and NaN handling

### **10.2: Advanced dplyr Functions**

When implemented in T:
- `slice()`, `slice_head()`, `slice_tail()`
- `distinct()`
- `rename()`
- `across()` (column-wise operations)
- `case_when()` (complex conditionals)
- `coalesce()` (NA replacement)
- `lag()`, `lead()` (window functions)
- `cumsum()`, `cummean()` (cumulative)

### **10.3: Advanced Stats Functions**

- Multiple regression with interactions
- ANOVA
- t-tests
- Chi-square tests
- Non-linear models

---

## **Summary Timeline**

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| 1. Nix Config | 2 days | R in flake, cachix configured |
| 2. Test Data | 1 day | 7 CSV datasets |
| 3. R Expected | 2 days | 40+ expected output CSVs |
| 4. T Scripts | 3 days | 40+ .t test scripts |
| 5. testthat | 2 days | Comparison suite |
| 6. Makefile | 1 day | `make golden` targets |
| 7. CI | 2 days | GitHub Actions workflow |
| 8. Test Cases | 2 days | Complete test matrix |
| 9. Docs | 1 day | README, coverage report |
| **Total** | **~3 weeks** | **Full TDD framework** |

---

## **Success Metrics**

✅ **Phase Complete When:**
- All 40+ test cases defined
- CI runs on every PR
- Coverage report shows % implemented
- Skipped tests document missing features
- README documents how to add tests

✅ **Project Success When:**
- 80%+ of tests passing (not skipped)
- All core colcraft verbs tested
- Stats functions have golden tests
- No regressions in CI

---

This gives you a production-ready, TDD-driven testing framework that will guide T's development toward R compatibility while catching bugs early! 🎯

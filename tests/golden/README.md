# Golden Tests - README

This directory contains the golden testing framework for comparing T language outputs against R (dplyr/stats) reference implementations.

## Directory Structure

```
tests/golden/
├── data/                    # Test datasets (generated from R)
│   └── *.csv               # CSV files (gitignored)
├── expected/                # Expected outputs from R
│   └── *.csv               # CSV files (gitignored)
├── t_outputs/               # Actual outputs from T
│   └── *.csv               # CSV files (gitignored)
├── t_scripts/               # T test scripts
│   └── *.t                 # Individual test scripts
├── generate_datasets.R      # Phase 2: Generate test data
├── generate_expected.R      # Phase 3: Generate dplyr outputs
├── generate_expected_stats.R # Phase 3: Generate stats outputs
├── run_all_t_tests.sh      # Phase 4: Run all T tests
└── test_golden_r.R         # Phase 5: Compare outputs with testthat
```

## Quick Start

### Using Make (Recommended)

```bash
# Run full golden test pipeline
make golden

# Run individual phases
make golden-setup      # Create directories
make golden-data       # Generate test datasets
make golden-expected   # Generate R expected outputs
make golden-run        # Run T test scripts
make golden-compare    # Compare T vs R outputs

# Quick test (assumes data already generated)
make golden-quick

# Clean generated files
make golden-clean
```

### Manual Execution

```bash
# 1. Setup directories
mkdir -p tests/golden/{data,expected,t_outputs}

# 2. Generate test data from R datasets
Rscript tests/golden/generate_datasets.R

# 3. Generate expected outputs using R/dplyr
Rscript tests/golden/generate_expected.R
Rscript tests/golden/generate_expected_stats.R

# 4. Run T test scripts
./tests/golden/run_all_t_tests.sh

# 5. Compare T outputs vs R expected
Rscript tests/golden/test_golden_r.R
```

## Implementation Phases

### ✅ Phase 1: Nix Configuration for R
- R with packages (dplyr, readr, testthat, etc.) added to `flake.nix`

### ✅ Phase 2: Test Data Generation
- `generate_datasets.R` creates test datasets:
  - mtcars, iris, airquality, chickweight, toothgrowth
  - simple.csv (for basic tests)
  - data_with_nas.csv (for NA handling tests)

### ✅ Phase 3: R Golden Outputs
- `generate_expected.R`: dplyr operations (select, filter, mutate, arrange, group_by)
- `generate_expected_stats.R`: statistical operations (lm, cor, summary stats)

### ✅ Phase 4: T Test Scripts
- 27 individual `.t` scripts in `tests/golden/t_scripts/`
- `run_all_t_tests.sh` executes all scripts and reports pass/fail/skip
- Test categories:
  - SELECT (3 tests)
  - FILTER (4 tests)
  - MUTATE (4 tests)
  - ARRANGE (3 tests)
  - GROUP_BY + SUMMARIZE (5 tests)
  - PIPELINES (5 tests)
  - NA HANDLING (3 tests - not yet implemented)

### ✅ Phase 5: R Comparison Tests with testthat
- `test_golden_r.R` uses testthat to compare T outputs vs R expected
- Includes `compare_csvs()` helper for robust comparison:
  - Row/column count validation
  - Column name matching
  - Numeric value comparison with tolerance
  - String value exact matching
- 31 test cases total (some marked as skipped for unimplemented features)

### ✅ Phase 6: Makefile Integration
- `Makefile` provides convenient targets for running the golden test pipeline
- Targets: `golden`, `golden-setup`, `golden-data`, `golden-expected`, `golden-run`, `golden-compare`, `golden-clean`, `golden-quick`

## Test Coverage

### Implemented Tests
- **SELECT**: Single column, multiple columns, reordering
- **FILTER**: Numeric comparisons, AND/OR conditions, string equality
- **MUTATE**: New columns, multiple mutations, overwriting columns, column ratios
- **ARRANGE**: Ascending, descending, multi-column sorting
- **GROUP_BY + SUMMARIZE**: Mean, multiple aggregations, multiple keys, various functions
- **PIPELINES**: Chained operations (filter→select, select→filter→arrange, etc.)

### Not Yet Implemented (Skipped in Tests)
- **NA Handling**: mean with na.rm, filtering NAs, group_by with NAs
- **Window Functions**: group_by → mutate
- **Linear Models**: lm() for regression
- **Correlations**: cor() for correlation analysis

## Test Execution Details

### T Test Scripts
Each `.t` script:
1. Loads a dataset from `tests/golden/data/`
2. Applies T language operations (select, filter, mutate, etc.)
3. Writes result to `tests/golden/t_outputs/`
4. Prints success message or skip warning

### Test Comparison
The R testthat script:
1. Loads expected output from `tests/golden/expected/`
2. Loads T output from `tests/golden/t_outputs/`
3. Compares dimensions, column names, and values
4. Reports pass/fail/skip for each test
5. Provides summary statistics

## Adding New Tests

### 1. Add to Phase 3 (R Expected Output)
Edit `generate_expected.R` or `generate_expected_stats.R`:
```r
mtcars %>%
  your_operation_here() %>%
  save_output("test_name", "description")
```

### 2. Add to Phase 4 (T Test Script)
Create `tests/golden/t_scripts/test_name.t`:
```
-- Test: Description
df = read_csv("tests/golden/data/dataset.csv")
result = df |> your_t_operation_here
write_csv(result, "tests/golden/t_outputs/test_name.csv")
print("✓ test_name complete")
```

### 3. Add to Phase 5 (Comparison Test)
Edit `test_golden_r.R`:
```r
test_that("Description", {
  compare_csvs("test_name")
})
```

## Continuous Integration

The golden tests are designed to be run in CI to ensure T outputs match R reference implementations. Add to your CI pipeline:

```yaml
- name: Run Golden Tests
  run: make golden
```

## Notes

- All CSV files in `data/`, `expected/`, and `t_outputs/` are gitignored
- Tests marked as "skipped" indicate features not yet implemented in T
- Floating-point comparisons use a tolerance of 1e-6 by default
- Test scripts use T's pipe operator `|>` for readability

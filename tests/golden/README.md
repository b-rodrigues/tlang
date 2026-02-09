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
├── test_golden_r.R              # testthat comparison suite
├── run_all_t_tests.sh           # Run all T test scripts
├── generate_coverage_report.R   # Generate coverage HTML report
├── data/                        # Generated CSV datasets (gitignored)
├── expected/                    # Expected outputs from R (gitignored)
├── t_outputs/                   # T outputs for comparison (gitignored)
└── t_scripts/                   # T test scripts (.t files)
    ├── mtcars_select_mpg.t
    ├── mtcars_filter_mpg_gt_20.t
    ├── mtcars_groupby_cyl_mean_mpg.t
    └── ... (27+ test scripts)
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

Edit `test_golden_r.R`:

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

# Makefile for T Language Golden Tests
# Phases 4-6 of Golden Testing Implementation

.PHONY: golden golden-setup golden-data golden-expected golden-run golden-compare golden-clean golden-quick

# Main golden test target - runs all phases
# Uses - prefix to continue on error for test execution steps
golden: golden-setup golden-data golden-expected
	@$(MAKE) golden-run
	@$(MAKE) golden-compare
	@echo ""
	@echo "✓ Golden test pipeline complete (check output above for any failures)"

# Setup: ensure directories exist
golden-setup:
	@echo "=== Setting up golden test directories ==="
	@mkdir -p tests/golden/data
	@mkdir -p tests/golden/expected
	@mkdir -p tests/golden/t_outputs
	@mkdir -p tests/golden/t_scripts
	@echo "✓ Directories created"

# Generate test data (R datasets -> CSV)
golden-data:
	@echo "=== Generating test datasets ==="
	@Rscript tests/golden/generate_datasets.R

# Generate expected outputs (R/dplyr -> CSV)
golden-expected:
	@echo "=== Generating expected outputs from R ==="
	@Rscript tests/golden/generate_expected.R
	@Rscript tests/golden/generate_expected_stats.R
	@Rscript tests/golden/generate_expected_window.R

# Run T tests (T -> CSV)
# Fail on error
golden-run:
	@echo "=== Running T test scripts ==="
	@./tests/golden/run_all_t_tests.sh

# Compare T outputs vs R expected (testthat)
# Fail on error
golden-compare:
	@echo "=== Comparing T outputs vs R expected ==="
	@Rscript tests/golden/test_golden_r.R

# Clean generated files
golden-clean:
	@echo "=== Cleaning golden test outputs ==="
	@rm -rf tests/golden/data/*.csv
	@rm -rf tests/golden/expected/*.csv
	@rm -rf tests/golden/t_outputs/*.csv
	@echo "✓ Cleaned"

# Quick check (assumes data and expected already generated)
# Fail on error
golden-quick:
	@$(MAKE) golden-run
	@$(MAKE) golden-compare
	@echo ""
	@echo "✓ Quick test complete (check output above for any failures)"

# Help message
help:
	@echo "Golden Test Makefile Targets:"
	@echo "  make golden          - Run full golden test pipeline"
	@echo "  make golden-setup    - Create required directories"
	@echo "  make golden-data     - Generate test datasets from R"
	@echo "  make golden-expected - Generate expected outputs from R"
	@echo "  make golden-run      - Run T test scripts"
	@echo "  make golden-compare  - Compare T outputs vs R expected"
	@echo "  make golden-clean    - Clean generated files"
	@echo "  make golden-quick    - Run tests (assumes data exists)"

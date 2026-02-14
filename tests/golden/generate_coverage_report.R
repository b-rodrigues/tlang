#!/usr/bin/env Rscript

# Generate a coverage report: which tests pass, which are skipped

library(dplyr)
library(readr)

expected_dir <- "tests/golden/expected"
t_output_dir <- "tests/golden/t_outputs"

expected_files <- list.files(expected_dir, pattern = "\\.csv$")
t_output_files <- list.files(t_output_dir, pattern = "\\.csv$")

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

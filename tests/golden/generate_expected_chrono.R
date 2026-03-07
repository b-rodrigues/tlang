#!/usr/bin/env Rscript

library(dplyr)
library(readr)
library(tibble)

output_dir <- "tests/golden/expected"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Generating expected chrono outputs...\n")

save_output <- function(df, name, operation) {
  filepath <- file.path(output_dir, paste0(name, ".csv"))
  write_csv(df, filepath)
  message(sprintf("✓ %s: %s (%d rows × %d cols)",
                  operation, name, nrow(df), ncol(df)))
}

message("=== CHRONO Tests ===")

component_df <- tibble(
  label = c("leap", "common"),
  date_str = c("2024-01-31", "2023-01-31"),
  ts_str = c("2024-07-04 14:30:45", "2024-01-15 09:05:07"),
  custom_date = c("15 Jan 2024", "03 Feb 2025")
) %>%
  mutate(
    d = as.Date(date_str),
    dt = as.POSIXct(ts_str, tz = "UTC", format = "%Y-%m-%d %H:%M:%S"),
    custom = as.Date(custom_date, format = "%d %b %Y"),
    year = as.integer(format(d, "%Y")),
    month_label = format(d, "%b"),
    month_num = as.integer(format(d, "%m")),
    day_num = as.integer(format(d, "%d")),
    weekday = format(d, "%a"),
    yday_num = as.integer(format(d, "%j")),
    quarter_num = ((month_num - 1) %/% 3) + 1L,
    next_month_fmt = vapply(
      d,
      function(x) format(seq(x, by = "month", length.out = 2)[2], "%Y-%m-%d"),
      character(1)
    ),
    custom_fmt = format(custom, "%Y-%m-%d"),
    dt_fmt = format(dt, "%Y-%m-%d %H:%M:%S", tz = "UTC")
  ) %>%
  select(label, year, month_label, month_num, day_num, weekday, yday_num, quarter_num, next_month_fmt, custom_fmt, dt_fmt)

save_output(component_df, "chrono_components", "chrono component extraction")

filter_arrange_df <- tibble(
  name = c("b", "a", "c"),
  date_str = c("2024-02-10", "2023-12-31", "2024-01-15")
) %>%
  mutate(d = as.Date(date_str)) %>%
  filter(d >= as.Date("2024-01-01")) %>%
  arrange(desc(d)) %>%
  transmute(name, date_fmt = format(d, "%Y-%m-%d"))

save_output(filter_arrange_df, "chrono_filter_arrange", "chrono filter + arrange")

message("\n✅ All chrono outputs generated!")

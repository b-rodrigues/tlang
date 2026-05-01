#!/usr/bin/env Rscript

library(dplyr)
library(lubridate)
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
    d = ymd(date_str),
    dt = ymd_hms(ts_str, tz = "UTC"),
    custom = dmy(custom_date),
    year = year(d),
    month_label = as.character(month(d, label = TRUE, abbr = TRUE)),
    month_num = month(d),
    day_num = day(d),
    weekday = as.character(wday(d, label = TRUE, abbr = TRUE)),
    yday_num = yday(d),
    quarter_num = quarter(d),
    next_month_fmt = format(d %m+% months(1), "%Y-%m-%d"),
    custom_fmt = format(custom, "%Y-%m-%d"),
    dt_fmt = format(dt, "%Y-%m-%d %H:%M:%S", tz = "UTC")
  ) %>%
  select(label, year, month_label, month_num, day_num, weekday, yday_num, quarter_num, next_month_fmt, custom_fmt, dt_fmt)

save_output(component_df, "chrono_components", "chrono component extraction")

filter_arrange_df <- tibble(
  name = c("b", "a", "c"),
  date_str = c("2024-02-10", "2023-12-31", "2024-01-15")
) %>%
  mutate(d = ymd(date_str)) %>%
  filter(d >= ymd("2024-01-01")) %>%
  arrange(desc(d)) %>%
  transmute(name, date_fmt = format(d, "%Y-%m-%d"))

save_output(filter_arrange_df, "chrono_filter_arrange", "chrono filter + arrange")

conversion_df <- tibble(
  label = c("leap_boundary", "iso_newyear"),
  us_str = c("02/29/2024", "01/01/2021"),
  eu_str = c("31/12/2020", "01/01/2021"),
  dt_str = c("2024-02-29 23:59:30", "2021-01-01 00:00:29"),
  day_offset = c(1, 31),
  unix_secs = c(86461, 0)
) %>%
  mutate(
    us = mdy(us_str),
    eu = dmy(eu_str),
    dt = ymd_hms(dt_str, tz = "UTC"),
    us_fmt = format(us, "%Y-%m-%d"),
    eu_fmt = format(eu, "%Y-%m-%d"),
    dt_fmt = format(dt, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    origin_date_fmt = format(as_date(day_offset, origin = ymd("2024-02-28")), "%Y-%m-%d"),
    origin_dt_fmt = format(as_datetime(unix_secs, origin = ymd("1970-01-01"), tz = "UTC"), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    made_date_fmt = format(make_date(year(us), month(us), day(us)), "%Y-%m-%d"),
    iso_week = isoweek(eu),
    iso_year = isoyear(eu),
    semester_num = semester(us),
    leap_flag = leap_year(us),
    days_month = days_in_month(us),
    hour_num = hour(dt),
    minute_num = minute(dt),
    second_num = second(dt),
    am_flag = am(dt),
    pm_flag = pm(dt),
    tz_label = tz(dt)
  ) %>%
  select(
    label, us_fmt, eu_fmt, dt_fmt, origin_date_fmt, origin_dt_fmt, made_date_fmt,
    iso_week, iso_year, semester_num, leap_flag, days_month,
    hour_num, minute_num, second_num, am_flag, pm_flag, tz_label
  )

save_output(conversion_df, "chrono_conversions", "chrono parsing and conversions")

rounding_interval_df <- tibble(
  label = c("down", "up"),
  date_str = c("2024-01-15", "2024-01-31"),
  dt_str = c("2024-01-15 09:29:29", "2024-01-15 09:37:42"),
  custom_dt_str = c("15 Jan 2024 09:29:29", "29 Feb 2024 23:59:59"),
  start_str = c("2024-01-01", "2024-02-01"),
  end_str = c("2024-01-31", "2024-02-29")
) %>%
  mutate(
    d = ymd(date_str),
    dt = ymd_hms(dt_str, tz = "UTC"),
    custom_dt = parse_date_time(custom_dt_str, orders = "d b Y HMS", tz = "UTC"),
    floor_month = format(floor_date(d, "month"), "%Y-%m-%d"),
    ceiling_month = format(ceiling_date(d, "month"), "%Y-%m-%d"),
    floor_hour = format(floor_date(dt, "hour"), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    ceiling_hour = format(ceiling_date(dt, "hour"), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    round_hour = format(round_date(dt, "hour"), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    custom_dt_fmt = format(custom_dt, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    plus_week = format(d + weeks(1), "%Y-%m-%d"),
    plus_days = format(d + days(10), "%Y-%m-%d"),
    inside = d %within% interval(ymd(start_str), ymd(end_str))
  ) %>%
  select(
    label, floor_month, ceiling_month, floor_hour, ceiling_hour,
    round_hour, custom_dt_fmt, plus_week, plus_days, inside
  )

save_output(rounding_interval_df, "chrono_rounding_intervals", "chrono rounding and interval logic")

message("\n✅ All chrono outputs generated!")

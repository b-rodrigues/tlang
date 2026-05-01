-- Test: chrono rounding, parsing, and interval logic against lubridate
result = dataframe([
  [
    label: "down",
    floor_month: format_date(floor_date(ymd("2024-01-15"), "month"), "%Y-%m-%d"),
    ceiling_month: format_date(ceiling_date(ymd("2024-01-15"), "month"), "%Y-%m-%d"),
    floor_hour: format_datetime(floor_date(ymd_hms("2024-01-15 09:29:29"), "hour"), "%Y-%m-%d %H:%M:%S"),
    ceiling_hour: format_datetime(ceiling_date(ymd_hms("2024-01-15 09:29:29"), "hour"), "%Y-%m-%d %H:%M:%S"),
    round_hour: format_datetime(round_date(ymd_hms("2024-01-15 09:29:29"), "hour"), "%Y-%m-%d %H:%M:%S"),
    custom_dt_fmt: format_datetime(parse_datetime("15 Jan 2024 09:29:29", "%d %b %Y %H:%M:%S", tz = "UTC"), "%Y-%m-%d %H:%M:%S"),
    plus_week: format_date(ymd("2024-01-15") + weeks(1), "%Y-%m-%d"),
    plus_days: format_date(ymd("2024-01-15") + days(10), "%Y-%m-%d"),
    inside: `%within%`(ymd("2024-01-15"), interval(ymd("2024-01-01"), ymd("2024-01-31")))
  ],
  [
    label: "up",
    floor_month: format_date(floor_date(ymd("2024-01-31"), "month"), "%Y-%m-%d"),
    ceiling_month: format_date(ceiling_date(ymd("2024-01-31"), "month"), "%Y-%m-%d"),
    floor_hour: format_datetime(floor_date(ymd_hms("2024-01-15 09:37:42"), "hour"), "%Y-%m-%d %H:%M:%S"),
    ceiling_hour: format_datetime(ceiling_date(ymd_hms("2024-01-15 09:37:42"), "hour"), "%Y-%m-%d %H:%M:%S"),
    round_hour: format_datetime(round_date(ymd_hms("2024-01-15 09:37:42"), "hour"), "%Y-%m-%d %H:%M:%S"),
    custom_dt_fmt: format_datetime(parse_datetime("29 Feb 2024 23:59:59", "%d %b %Y %H:%M:%S", tz = "UTC"), "%Y-%m-%d %H:%M:%S"),
    plus_week: format_date(ymd("2024-01-31") + weeks(1), "%Y-%m-%d"),
    plus_days: format_date(ymd("2024-01-31") + days(10), "%Y-%m-%d"),
    inside: `%within%`(ymd("2024-01-31"), interval(ymd("2024-02-01"), ymd("2024-02-29")))
  ]
])

write_csv(result, "tests/golden/t_outputs/chrono_rounding_intervals.csv")
print("✓ chrono rounding/intervals complete")

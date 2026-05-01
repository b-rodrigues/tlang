-- Test: chrono parsing, conversions, and extraction against lubridate
result = dataframe([
  [
    label: "leap_boundary",
    us_fmt: format_date(mdy("02/29/2024"), "%Y-%m-%d"),
    eu_fmt: format_date(dmy("31/12/2020"), "%Y-%m-%d"),
    dt_fmt: format_datetime(ymd_hms("2024-02-29 23:59:30"), "%Y-%m-%d %H:%M:%S"),
    origin_date_fmt: format_date(as_date(1, origin = "2024-02-28"), "%Y-%m-%d"),
    origin_dt_fmt: format_datetime(as_datetime(86461, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d %H:%M:%S"),
    made_date_fmt: format_date(make_date(year = 2024, month = 2, day = 29), "%Y-%m-%d"),
    iso_week: isoweek(dmy("31/12/2020")),
    iso_year: isoyear(dmy("31/12/2020")),
    semester_num: semester(mdy("02/29/2024")),
    leap_flag: is_leap_year(mdy("02/29/2024")),
    days_month: days_in_month(mdy("02/29/2024")),
    hour_num: hour(ymd_hms("2024-02-29 23:59:30")),
    minute_num: minute(ymd_hms("2024-02-29 23:59:30")),
    second_num: second(ymd_hms("2024-02-29 23:59:30")),
    am_flag: am(ymd_hms("2024-02-29 23:59:30")),
    pm_flag: pm(ymd_hms("2024-02-29 23:59:30")),
    tz_label: tz(ymd_hms("2024-02-29 23:59:30"))
  ],
  [
    label: "iso_newyear",
    us_fmt: format_date(mdy("01/01/2021"), "%Y-%m-%d"),
    eu_fmt: format_date(dmy("01/01/2021"), "%Y-%m-%d"),
    dt_fmt: format_datetime(ymd_hms("2021-01-01 00:00:29"), "%Y-%m-%d %H:%M:%S"),
    origin_date_fmt: format_date(as_date(31, origin = "2024-02-28"), "%Y-%m-%d"),
    origin_dt_fmt: format_datetime(as_datetime(0, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d %H:%M:%S"),
    made_date_fmt: format_date(make_date(year = 2021, month = 1, day = 1), "%Y-%m-%d"),
    iso_week: isoweek(dmy("01/01/2021")),
    iso_year: isoyear(dmy("01/01/2021")),
    semester_num: semester(mdy("01/01/2021")),
    leap_flag: is_leap_year(mdy("01/01/2021")),
    days_month: days_in_month(mdy("01/01/2021")),
    hour_num: hour(ymd_hms("2021-01-01 00:00:29")),
    minute_num: minute(ymd_hms("2021-01-01 00:00:29")),
    second_num: second(ymd_hms("2021-01-01 00:00:29")),
    am_flag: am(ymd_hms("2021-01-01 00:00:29")),
    pm_flag: pm(ymd_hms("2021-01-01 00:00:29")),
    tz_label: tz(ymd_hms("2021-01-01 00:00:29"))
  ]
])

write_csv(result, "tests/golden/t_outputs/chrono_conversions.csv")
print("✓ chrono conversions complete")

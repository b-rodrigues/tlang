# chrono

Date and datetime parsing, extraction, formatting, and calendar arithmetic.

## Functions

| Function | Description |
|----------|-------------|
| `ymd(s)` / `mdy(s)` / `dmy(s)` / `ydm(s)` | Parse common date string layouts into `Date` values |
| `ymd_h(s)` / `ymd_hm(s)` / `ymd_hms(s)` | Parse common datetime layouts into `Datetime` values |
| `parse_date(s, format)` | Parse a date with a custom `strptime`-style format |
| `parse_datetime(s, format)` | Parse a datetime with a custom `strptime`-style format |
| `today()` / `now()` | Return the current UTC date or datetime |
| `year(x)` / `month(x)` / `day(x)` / `mday(x)` | Extract calendar components |
| `yday(x)` / `wday(x)` / `week(x)` / `isoweek(x)` / `isoyear(x)` | Extract day/week-based components |
| `quarter(x)` / `semester(x)` | Extract larger calendar partitions |
| `hour(x)` / `minute(x)` / `second(x)` / `tz(x)` | Extract time-of-day and timezone information |
| `years(n)` / `months(n)` / `weeks(n)` / `days(n)` | Construct calendar periods |
| `hours(n)` / `minutes(n)` / `seconds(n)` | Construct time periods |
| `milliseconds(n)` / `microseconds(n)` / `nanoseconds(n)` | Construct sub-second periods |
| `make_period(...)` | Build a `Period` value from named fields |
| `period_years(p)` / `period_months(p)` / `period_days(p)` | Read period fields |
| `period_hours(p)` / `period_minutes(p)` / `period_seconds(p)` | Read time fields from a period |
| `format_date(x, format)` | Format a date-like value as a string |
| `format_datetime(x, format)` | Format a datetime-like value as a string |
| `as_date(x)` / `as_datetime(x)` | Convert strings and numeric offsets to date-like values |
| `interval(start, end)` / `` `%within%`(x, interval) `` | Construct intervals and test whether a date-like value falls inside one |
| `floor_date(x, unit)` / `ceiling_date(x, unit)` / `round_date(x, unit)` | Round date-like values to `second`, `minute`, `hour`, `day`, `month`, or `year` boundaries |
| `with_tz(x, tz)` / `force_tz(x, tz)` | Current implementation treats timezones as labels only, so both update the attached timezone label without offset conversion |
| `is_leap_year(x)` / `days_in_month(x)` | Calendar helpers for leap-year and month-length checks |
| `is_date(x)` / `is_datetime(x)` / `is_period(x)` / `is_duration(x)` / `is_interval(x)` | Type predicates for chrono values |

## Notes

- Dates are stored as days since the Unix epoch (`1970-01-01`).
- Datetimes are stored as microseconds since the Unix epoch.
- Parsing helpers accept either a single string or a `Vector[String]`.
- Component extractors are vectorized over `Vector` inputs.
- Date arithmetic supports expressions like `ymd("2024-01-31") + months(1)`.
- Rounding helpers preserve the input kind: `Date` values stay dates for day/month/year rounding, while `Datetime` values preserve their timezone label.

## Examples

```t
d = ymd("2024-07-04")
dt = ymd_hms("2024-07-04 14:30:45")

year(d)                         -- 2024
month(d, label = true)          -- "Jul"
format_date(d, "%Y-%m-%d")      -- "2024-07-04"

ymd("2024-01-31") + months(1)   -- Date(2024-02-29)
parse_date("15 Jan 2024", "%d %b %Y")
parse_datetime("2024-07-04 14:30:45", "%Y-%m-%d %H:%M:%S")
floor_date(dt, "hour")
`%within%`(d, interval(ymd("2024-07-01"), ymd("2024-07-31")))
```

## Status

Built-in package — included with T by default.

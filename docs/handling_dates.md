# Handling Dates and Times in T

The `chrono` package provides comprehensive tools for working with dates and times, heavily inspired by R's `lubridate`. 

## Core Types

T supports several temporal types:
- **Date**: A calendar date (e.g., `2024-03-08`).
- **Datetime**: A precise point in time with a timezone label.
- **Interval**: A span of time between two specific instants.
- **Period**: A human-friendly duration (e.g., "2 months and 3 days").
- **Duration**: A precise physical duration in seconds.

## Parsing Dates

You can parse strings into dates using shorthand helpers:

```t
d1 = ymd("2024-01-15")
d2 = mdy("01-15-2024")
d3 = dmy("15-01-2024")

dt1 = ymd_hms("2024-01-15 09:30:00")
dt2 = ymd_hm("2024-01-15 09:30")
```

For custom formats, use `parse_date` or `parse_datetime`:

```t
d = parse_date("15 Jan 2024", "%d %b %Y")
```

## Creating Dates from Components

If you have numeric components, use `make_date` or `make_datetime`:

```t
d = make_date(year = 2024, month = 3, day = 8)
dt = make_datetime(year = 2024, month = 3, day = 8, hour = 12, min = 0, sec = 0, tz = "Europe/Paris")
```

## Component Extraction

Extract specific parts of a date or datetime:

```t
year(d)       -- 2024
month(d)      -- 3
month(d, label = true) -- "Mar"
day(d)        -- 8
wday(d)       -- Week day (1-7)
hour(dt)      -- 12
am(dt)        -- true
pm(dt)        -- false
```

## Date Arithmetic

T supports intuitive date arithmetic using periods:

```t
-- Add 3 months to a date
next_app = ymd("2024-01-31") + months(3) -- 2024-04-30

-- Subtract 1 week
last_week = today() - weeks(1)
```

Arithmetic is "calendar-aware". Adding a month to January 31st results in the last day of February.

## Rounding

Round dates to the nearest calendar unit:

```t
floor_date(dt, "hour")    -- Round down to start of hour
ceiling_date(d, "month")  -- Round up to start of next month
round_date(dt, "day")     -- Round to nearest day
```

## Intervals and %within%

Intervals represent a fixed span of time. You can check if a date falls within an interval using the `%within%` operator:

```t
vacation = interval(ymd("2024-07-01"), ymd("2024-07-15"))
ymd("2024-07-04") %within% vacation -- true
```

## Timezones

Timezones in T are currently handled as labels. 

- `with_tz(dt, tz)`: Changes the timezone label without altering the underlying time.
- `force_tz(dt, tz)`: Similar to `with_tz`, used to clarify or correct a timezone label.

## Example Workflow

```t
df = read_csv("sales.t") |>
  mutate(
    date = ymd($order_date),
    month = month($date, label = true),
    quarter = quarter($date)
  ) |>
  filter(year($date) == 2024) |>
  group_by($month) |>
  summarize($total = sum($sales))
```

---

## Next Steps

Now that you can handle temporal data, explore text processing and categorical data in T:

1. **[String Manipulation](string_manipulation.md)** — Explore powerful functions for text processing and regular expressions.
2. **[Factors & Categorical Data](factors.md)** — Learn how to work with categorical data.
3. **[Arrays and Matrices](arrays.md)** — Vector and matrix operations.
4. **[API Reference](api-reference.md)** — Complete function reference by package.

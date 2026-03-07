# Date and Datetime Support in T

T provides first-class support for date and datetime values in DataFrames, with a
manipulation API inspired by the R package **lubridate**. Dates and datetimes are
stored as typed Arrow columns, ensuring zero-copy interoperability with R and Python.

---

## Table of Contents

1. [Type System](#1-type-system)
2. [Date Columns in DataFrames](#2-date-columns-in-dataframes)
3. [Parsing Dates and Datetimes](#3-parsing-dates-and-datetimes)
4. [Extracting Components](#4-extracting-components)
5. [Date Arithmetic and Periods](#5-date-arithmetic-and-periods)
6. [Durations](#6-durations)
7. [Intervals](#7-intervals)
8. [Rounding Dates](#8-rounding-dates)
9. [Timezones](#9-timezones)
10. [Formatting Dates](#10-formatting-dates)
11. [Conversion Helpers](#11-conversion-helpers)
12. [Using Dates with Colcraft Verbs](#12-using-dates-with-colcraft-verbs)
13. [NA and Error Semantics](#13-na-and-error-semantics)
14. [Arrow Backend Integration](#14-arrow-backend-integration)
15. [Implementation Roadmap](#15-implementation-roadmap)

---

## 1. Type System

### New Arrow Column Types

Two new `column_data` variants are added to `src/arrow/arrow_table.ml`:

```ocaml
type column_data =
  | ...
  | DateColumn     of int option array          (* days since Unix epoch, i.e. Arrow Date32 *)
  | DatetimeColumn of int64 option array * string option
  (* microseconds since Unix epoch, optional timezone string — Arrow Timestamp(us, tz?) *)
```

And two corresponding `arrow_type` tags:

```ocaml
type arrow_type =
  | ...
  | ArrowDate       (* Arrow Date32 — calendar date only *)
  | ArrowTimestamp of string option  (* Arrow Timestamp(us, tz?) *)
```

### New `value` Variants (AST)

Two new variants are added to the `value` type in `src/ast.ml`:

```ocaml
and value =
  | ...
  | VDate     of int          (* days since 1970-01-01, inclusive *)
  | VDatetime of int64 * string option
  (* microseconds since 1970-01-01T00:00:00Z, optional IANA timezone name *)
```

Both are **immutable scalars**. There is no mutable date object.

### NA Semantics

Missing dates are represented with `VNA NADate` (a new tag) or the existing
`VNA NAGeneric`. In a `DateColumn`, `None` entries are treated as NA.

---

## 2. Date Columns in DataFrames

### Reading Dates from CSV

`read_csv` gains an optional `col_types` parameter that lets the caller hint
which columns should be parsed as dates:

```t
-- Hint that "created_at" is a date and "logged_at" is a datetime
df = read_csv("events.csv", col_types = [
  created_at: "date",
  logged_at:  "datetime"
])
```

When no hint is provided for a column T uses heuristic detection:
* If every non-empty value in a string column matches `YYYY-MM-DD`, it is
  silently promoted to `ArrowDate`.
* If every non-empty value matches `YYYY-MM-DDTHH:MM:SS` (with or without a
  timezone offset), it is promoted to `ArrowTimestamp`.

Heuristic detection can be disabled with `col_types = [my_col: "string"]`.

### Constructing a Date Column with `mutate`

```t
df |> mutate($released = ymd($release_str))
df |> mutate($ts       = ymd_hms($ts_str))
```

### Inspecting Column Types

`colnames_with_types(df)` (or the existing `explain(df)`) shows `Date` /
`Datetime(tz)` in the column type list.

---

## 3. Parsing Dates and Datetimes

All parsing functions are in the new `chrono` package. They accept either a
`VString` scalar or a `VVector` of strings and return a `VDate`, `VDatetime`,
or `VVector` of the corresponding type (or a `VError` / `VVector` containing
`VNA` on failure).

### Format-Shorthand Parsers (lubridate style)

These parsers are tolerant of common separators (`-`, `/`, `.`, ` `, or none)
between the date fields.

| Function | Field Order | Example Input |
|----------|-------------|---------------|
| `ymd(s)` | Year-Month-Day | `"2024-01-15"`, `"20240115"` |
| `mdy(s)` | Month-Day-Year | `"01/15/2024"` |
| `dmy(s)` | Day-Month-Year | `"15-01-2024"` |
| `ydm(s)` | Year-Day-Month | `"2024-15-01"` |
| `ymd_h(s)` | Y-M-D + Hour | `"2024-01-15 09"` |
| `ymd_hm(s)` | Y-M-D + H:M | `"2024-01-15 09:30"` |
| `ymd_hms(s)` | Y-M-D + H:M:S | `"2024-01-15 09:30:00"` |
| `mdy_hms(s)` | M-D-Y + H:M:S | `"01/15/2024 09:30:00"` |
| `dmy_hms(s)` | D-M-Y + H:M:S | `"15-01-2024 09:30:00"` |

```t
d  = ymd("2024-01-15")           -- VDate
dt = ymd_hms("2024-01-15 09:30:00")  -- VDatetime
```

### Custom-Format Parser

```t
parse_date(s, format)
parse_datetime(s, format)
```

The `format` string follows `strptime` conventions:

| Token | Meaning |
|-------|---------|
| `%Y`  | 4-digit year |
| `%m`  | 2-digit month (01–12) |
| `%d`  | 2-digit day (01–31) |
| `%H`  | Hour (00–23) |
| `%M`  | Minute (00–59) |
| `%S`  | Second (00–60) |
| `%b`  | Abbreviated month name (`Jan`, `Feb`, …) |
| `%B`  | Full month name (`January`, …) |
| `%z`  | UTC offset (`+0200`, `-0500`) |
| `%Z`  | Timezone abbreviation (`UTC`, `EST`) |

```t
d  = parse_date("15 Jan 2024", "%d %b %Y")
dt = parse_datetime("2024/01/15 09:30:00+02:00", "%Y/%m/%d %H:%M:%S%z")
```

On parse failure both functions return `VError { code = ValueError; … }` for
scalar inputs and `VNA NAGeneric` for the failing element of a vector input
(consistent with how `as_float` behaves on non-numeric strings).

### `today()` and `now()`

```t
today()    -- VDate representing the current calendar date (UTC)
now()      -- VDatetime representing the current instant (UTC, microsecond precision)
now(tz = "America/New_York")  -- with explicit timezone
```

---

## 4. Extracting Components

All component-extraction functions accept either a `VDate` / `VDatetime`
scalar or a `VVector` of those types and return the corresponding integer (or
string) scalar / vector.

### Date Components

```t
year(d)          -- Int: calendar year (e.g. 2024)
month(d)         -- Int: month of year, 1–12
month(d, label = true)   -- String: abbreviated month name ("Jan"…"Dec")
day(d)           -- Int: day of month, 1–31
mday(d)          -- alias for day(d)
yday(d)          -- Int: day of year, 1–366
wday(d)          -- Int: day of week, 1 (Sunday) – 7 (Saturday)
wday(d, label = true)    -- String: abbreviated weekday ("Sun"…"Sat")
wday(d, week_start = 1)  -- Change first day of week: 1 = Monday, 7 = Sunday
week(d)          -- Int: ISO week number, 1–53
isoweek(d)       -- Int: ISO 8601 week number
isoyear(d)       -- Int: ISO 8601 week-numbering year (differs from year() near year boundary)
quarter(d)       -- Int: calendar quarter, 1–4
semester(d)      -- Int: half-year, 1–2
```

### Datetime Components

```t
hour(dt)         -- Int: hour, 0–23
minute(dt)       -- Int: minute, 0–59
second(dt)       -- Float: seconds including fractional part (0.0–60.999…)
tz(dt)           -- String: IANA timezone name, or "UTC" if unset
```

### Examples

```t
d = ymd("2024-07-04")

year(d)    -- 2024
month(d)   -- 7
day(d)     -- 4
wday(d)    -- 5  (Thursday; 1 = Sunday)
yday(d)    -- 186
quarter(d) -- 3

dt = ymd_hms("2024-07-04 14:30:45")
hour(dt)   -- 14
minute(dt) -- 30
second(dt) -- 45.0
```

---

## 5. Date Arithmetic and Periods

T distinguishes **periods** (human-calendar units) from **durations**
(exact elapsed time in seconds). This mirrors lubridate's philosophy: adding
`months(1)` to `ymd("2024-01-31")` yields `ymd("2024-02-29")` (the last day
of February in a leap year), not a fixed 30-day offset.

### Period Constructors

```t
years(n)      -- Period of n calendar years
months(n)     -- Period of n calendar months
weeks(n)      -- Period of n calendar weeks (7 * n days)
days(n)       -- Period of n calendar days
hours(n)      -- Period of n clock hours
minutes(n)    -- Period of n clock minutes
seconds(n)    -- Period of n clock seconds
milliseconds(n)
microseconds(n)
nanoseconds(n)
```

All period constructors return a `VPeriod` value:

```ocaml
(* In ast.ml *)
and period = {
  p_years   : int;
  p_months  : int;
  p_days    : int;
  p_hours   : int;
  p_minutes : int;
  p_seconds : int;
  p_micros  : int;
}

and value =
  | ...
  | VPeriod of period
```

### Arithmetic on Dates and Datetimes

The `+` and `-` operators are overloaded for date/datetime ± period:

```t
ymd("2024-01-31") + months(1)   -- ymd("2024-02-29")  (leap year 2024)
ymd("2023-01-31") + months(1)   -- ymd("2023-02-28")  (non-leap year)
ymd("2024-03-15") - days(10)    -- ymd("2024-03-05")
ymd_hms("2024-01-01 00:00:00") + hours(25) -- ymd_hms("2024-01-02 01:00:00")
```

Subtracting two dates yields a `VPeriod` (in days):

```t
ymd("2024-07-04") - ymd("2024-01-01")   -- days(185)
```

### Period Accessors

```t
period_years(p)
period_months(p)
period_days(p)
period_hours(p)
period_minutes(p)
period_seconds(p)
```

### `make_period`

```t
make_period(years = 0, months = 0, days = 0, hours = 0, minutes = 0, seconds = 0)
```

---

## 6. Durations

A **duration** is an exact elapsed time measured in (fractional) seconds,
independent of DST changes or leap years.

```ocaml
(* In ast.ml *)
and value =
  | ...
  | VDuration of float  (* total seconds, can be negative *)
```

### Duration Constructors

```t
dyears(n)        -- n * 365.25 * 86400 seconds
dmonths(n)       -- n * 365.25 / 12 * 86400 seconds (approximate)
dweeks(n)        -- n * 7 * 86400 seconds
ddays(n)         -- n * 86400 seconds
dhours(n)        -- n * 3600 seconds
dminutes(n)      -- n * 60 seconds
dseconds(n)      -- n seconds
dmilliseconds(n) -- n / 1000 seconds
dmicroseconds(n) -- n / 1_000_000 seconds
```

### Duration Arithmetic

```t
ymd_hms("2024-01-01 00:00:00") + dhours(36)
-- ymd_hms("2024-01-02 12:00:00")
-- (fixed offset — ignores DST; differs from + hours(36) when DST exists)
```

Subtracting two datetimes yields a `VDuration`:

```t
dt2 - dt1   -- VDuration of elapsed seconds
```

### Duration Accessors

```t
as_seconds(dur)
as_minutes(dur)
as_hours(dur)
as_days(dur)
as_weeks(dur)
```

---

## 7. Intervals

An **interval** is a directed span between two specific instants.

```ocaml
(* In ast.ml *)
and interval = {
  iv_start : int64;   (* microseconds since epoch *)
  iv_end   : int64;
  iv_tz    : string option;
}

and value =
  | ...
  | VInterval of interval
```

### Constructing Intervals

```t
interval(start_date, end_date)   -- inclusive start, exclusive end

-- Infix alias:
ymd("2024-01-01") %--% ymd("2024-12-31")
```

### Interval Operations

```t
int_start(iv)           -- VDatetime: start of interval
int_end(iv)             -- VDatetime: end of interval
int_length(iv)          -- VDuration: total length in seconds
int_flip(iv)            -- VInterval: reversed interval (start and end swapped)

int_overlaps(iv1, iv2)  -- Bool: do the two intervals overlap?
int_aligns_start(iv1, iv2)
int_aligns_end(iv1, iv2)
int_within(iv1, iv2)    -- Bool: is iv1 entirely within iv2?
```

### Converting Intervals

```t
as_duration(iv)  -- VDuration: total seconds
as_period(iv)    -- VPeriod: approximate calendar period
```

### Checking Whether a Date Falls in an Interval

```t
d %within% iv   -- Bool: is date d inside interval iv?
```

---

## 8. Rounding Dates

```t
floor_date(dt, unit)    -- truncate to the start of the given unit
ceiling_date(dt, unit)  -- round up to the start of the next unit
round_date(dt, unit)    -- round to the nearest unit boundary
```

Valid `unit` strings: `"second"`, `"minute"`, `"hour"`, `"day"`, `"week"`,
`"month"`, `"bimonth"`, `"quarter"`, `"halfyear"`, `"year"`.

```t
dt = ymd_hms("2024-07-04 14:37:22")

floor_date(dt, "hour")    -- ymd_hms("2024-07-04 14:00:00")
ceiling_date(dt, "day")   -- ymd_hms("2024-07-05 00:00:00")
round_date(dt, "month")   -- ymd_hms("2024-07-01 00:00:00")
floor_date(dt, "quarter") -- ymd_hms("2024-07-01 00:00:00")
```

---

## 9. Timezones

T uses **IANA timezone names** (e.g. `"America/New_York"`, `"Europe/Paris"`,
`"UTC"`) exclusively. Numeric offsets like `"+05:30"` are not first-class
values but may appear in parsed strings.

```t
-- Return the timezone of a datetime
tz(dt)                  -- String: IANA name or "UTC"

-- Re-interpret the same wall-clock time in a different timezone
-- (the underlying instant changes)
with_tz(dt, "America/Chicago")

-- Keep the same instant; relabel the timezone
-- (the wall-clock representation changes)
force_tz(dt, "America/Chicago")
```

Converting between timezones:

```t
utc_dt   = ymd_hms("2024-07-04 12:00:00", tz = "UTC")
ny_dt    = with_tz(utc_dt, "America/New_York")
-- "2024-07-04 08:00:00 America/New_York"
```

### Listing Available Timezones

```t
olson_names()  -- VVector of String: all IANA timezone names known to the runtime
```

---

## 10. Formatting Dates

```t
format_date(d, format)     -- String
format_datetime(dt, format)  -- String
```

The `format` string follows `strftime` conventions (same tokens as `parse_date`).

```t
format_date(ymd("2024-07-04"), "%B %d, %Y")   -- "July 04, 2024"
format_datetime(now(), "%Y-%m-%dT%H:%M:%SZ")  -- ISO 8601 UTC string
```

### Stamp: Reusable Formatter

`stamp` creates a formatting function from a representative example string:

```t
fmt = stamp("March 1, 1999")           -- infers "%B %d, %Y"
fmt(ymd("2024-07-04"))                  -- "July 04, 2024"

fmt_dt = stamp("1999-01-01 00:00:00")  -- infers "%Y-%m-%d %H:%M:%S"
fmt_dt(now())
```

---

## 11. Conversion Helpers

```t
-- String → Date / Datetime (lenient: tries common formats in order)
as_date(x)      -- VDate  (accepts VString, VDatetime, VInt days-since-epoch)
as_datetime(x)  -- VDatetime (accepts VString, VDate, VInt/VFloat epoch seconds)

-- Date ↔ Datetime
as_date(dt)     -- drops time component; returns VDate
as_datetime(d)  -- midnight UTC; returns VDatetime

-- Numeric ↔ Date
as_date(n, origin = "1970-01-01")       -- n days since origin → VDate
as_datetime(n, origin = "1970-01-01")   -- n seconds since origin → VDatetime

-- Type predicates
is_date(x)       -- Bool
is_datetime(x)   -- Bool
is_period(x)     -- Bool
is_duration(x)   -- Bool
is_interval(x)   -- Bool
```

---

## 12. Using Dates with Colcraft Verbs

Date columns integrate seamlessly with all existing colcraft verbs because
`VDate` and `VDatetime` values support the standard comparison and arithmetic
operators.

### `filter` by Date

```t
df |> filter($created_at >= ymd("2024-01-01"))
df |> filter(int_within($event_ts, interval(ymd("2024-01-01"), ymd("2024-04-01"))))
```

### `mutate` to Create Derived Date Columns

```t
df
  |> mutate($year     = year($created_at))
  |> mutate($month    = month($created_at))
  |> mutate($weekday  = wday($created_at, label = true))
  |> mutate($age_days = today() - $created_at)
```

### `arrange` by Date

```t
df |> arrange($event_ts)           -- ascending
df |> arrange($event_ts, "desc")   -- descending
```

### `group_by` on Date Components

```t
df
  |> mutate($month = floor_date($event_ts, "month"))
  |> group_by($month)
  |> summarize($n = nrow())
```

### Window Functions with Dates

All existing window functions (`lag`, `lead`, `cumsum`, etc.) work over date
columns. For `lag` and `lead`, the returned values are `VDate` / `VDatetime`
(shifted by row position, not by a calendar period). Period-aware lag is
implemented via `mutate` + arithmetic:

```t
-- Compute the gap in days between consecutive events per user
df
  |> group_by($user_id)
  |> arrange($event_ts)
  |> mutate($prev_ts  = lag($event_ts))
  |> mutate($gap_days = as_days($event_ts - $prev_ts))
```

---

## 13. NA and Error Semantics

Date handling follows the same rules as the rest of T:

* **No silent NA propagation.** If a date function receives `VNA`, it returns
  `VNA NAGeneric` (or `VNA NADate`), and the error is visible to the caller.
* **Parse failure = error for scalars.** `ymd("not a date")` returns
  `VError { code = ValueError; message = "Function \`ymd\` could not parse \"not a date\" as a date." }`.
* **Parse failure = NA for vector elements.** When a vector contains one bad
  element, that element becomes `VNA NAGeneric`; the rest are parsed normally.
* **Arithmetic on NA propagates NA.** `ymd("2024-01-01") + days(VNA NAInt)`
  returns `VNA NAGeneric`.
* **na_rm support.** Aggregation functions that accept `na_rm` (e.g. `min`,
  `max`) work correctly on date vectors with NA values.

---

## 14. Arrow Backend Integration

### New `arrow_type` Variants

```ocaml
(* src/arrow/arrow_table.ml *)
type arrow_type =
  | ...
  | ArrowDate                    (* Arrow Date32: days since epoch, 32-bit int *)
  | ArrowTimestamp of string option
  (* Arrow Timestamp(us, tz?): microseconds since epoch, optional IANA tz *)
```

### New `column_data` Variants

```ocaml
| DateColumn     of int option array
  (* None = NA; int = days since 1970-01-01 *)
| DatetimeColumn of int64 option array * string option
  (* None = NA; int64 = μs since epoch; string option = IANA tz *)
```

### CSV Reading

`arrow_io.ml` (or `arrow_ffi.ml`) must map Arrow's native `Date32` and
`Timestamp` types from the C GLib layer to the new column variants on read, and
convert back on write. The `col_types` hint in `read_csv` is forwarded to Arrow
as a schema hint before parsing.

### Arrow ↔ T Value Bridge

In `arrow_bridge.ml`:

```ocaml
let column_to_values = function
  | DateColumn arr ->
    Array.map (function
      | None   -> VNA NAGeneric
      | Some d -> VDate d) arr
  | DatetimeColumn (arr, tz) ->
    Array.map (function
      | None   -> VNA NAGeneric
      | Some t -> VDatetime (t, tz)) arr
  | ...

let values_to_column values =
  match values.(0) with
  | VDate _ ->
    DateColumn (Array.map (function
      | VDate d       -> Some d
      | VNA _         -> None
      | _             -> None  (* type mismatch — caller checked earlier *)) values)
  | VDatetime (_, tz) ->
    DatetimeColumn (
      Array.map (function
        | VDatetime (t, _) -> Some t
        | VNA _            -> None
        | _                -> None) values,
      tz)
  | ...
```

### Interop with R and Python

When an Arrow table with `ArrowDate` / `ArrowTimestamp` columns is serialized
to Feather or IPC and passed to R/Python:

* R receives the column as `Date` / `POSIXct` automatically (Arrow C GLib
  handles the schema mapping).
* Python/pandas receives it as `datetime64[us]` / `date` depending on the
  column type.

No extra conversion step is required in the T pipeline.

---

## 15. Implementation Roadmap

### Package: `chrono`

All date/datetime functions live in a new `src/packages/chrono/` package,
following the one-file-per-function convention:

```
src/packages/chrono/
├── README.md
├── loader.ml         -- registers all functions
├── ymd.ml            -- ymd, mdy, dmy, …
├── ymd_hms.ml        -- ymd_h, ymd_hm, ymd_hms, …
├── parse_date.ml     -- parse_date, parse_datetime
├── today.ml          -- today, now
├── components.ml     -- year, month, day, mday, yday, wday, week, …
├── time_components.ml -- hour, minute, second, tz
├── period.ml         -- years, months, weeks, days, hours, minutes, seconds, …
├── duration.ml       -- dyears, dmonths, … dseconds
├── interval.ml       -- interval, int_start, int_end, int_length, …
├── round_date.ml     -- floor_date, ceiling_date, round_date
├── timezone.ml       -- with_tz, force_tz, olson_names
├── format_date.ml    -- format_date, format_datetime, stamp
└── conversion.ml     -- as_date, as_datetime, is_date, is_datetime, …
```

`chrono` is loaded automatically as part of the default package set (alongside
`core`, `math`, `stats`, etc.).

### Phase 1 — Core Types and Scalar Operations

- [ ] Add `VDate`, `VDatetime`, `VPeriod`, `VDuration`, `VInterval` to `src/ast.ml`
- [ ] Add `ArrowDate`, `ArrowTimestamp` to `src/arrow/arrow_table.ml`
- [ ] Add `DateColumn`, `DatetimeColumn` to `column_data`
- [ ] Implement `arrow_bridge.ml` conversions for date types
- [ ] Implement `today` / `now`
- [ ] Implement all format-shorthand parsers (`ymd`, `mdy`, etc.)
- [ ] Implement `parse_date` / `parse_datetime` with `strptime`-format strings
- [ ] Implement all component extractors (`year`, `month`, …, `wday`, `yday`, …)
- [ ] Implement period constructors and date ± period arithmetic
- [ ] Implement duration constructors and date ± duration arithmetic
- [ ] Implement interval constructors and operations
- [ ] Add unit tests for all scalar operations

### Phase 2 — Vectorised / DataFrame Operations

- [ ] Implement vectorised path for all component extractors over `VVector`
- [ ] Implement vectorised path for parsing functions over `VVector`
- [ ] Ensure `DateColumn` and `DatetimeColumn` round-trip through `read_csv` / `write_csv`
- [ ] Implement `col_types` hint in `read_csv`
- [ ] Implement `colnames_with_types` output for date columns
- [ ] Add golden tests comparing T output to R lubridate/base output

### Phase 3 — Timezone and Formatting

- [ ] Implement `with_tz` / `force_tz` using the system IANA tz database
- [ ] Implement `olson_names()`
- [ ] Implement `format_date` / `format_datetime` using `strftime`
- [ ] Implement `stamp`
- [ ] Add timezone-aware golden tests

### Phase 4 — Rounding and Conversion Helpers

- [ ] Implement `floor_date` / `ceiling_date` / `round_date` for all units
- [ ] Implement `as_date` / `as_datetime` with all accepted input types
- [ ] Implement type-predicate helpers (`is_date`, etc.)
- [ ] Arithmetic between two dates/datetimes returning `VPeriod` / `VDuration`
- [ ] Add `%within%` and `%--%` infix operators in the parser

---

## Open Questions

1. **Calendar epoch**: T uses the POSIX epoch (1970-01-01) matching Arrow and
   R. Dates before 1970 are represented as negative integers.

2. **Sub-second precision**: `VDatetime` uses microseconds (matching Arrow's
   `Timestamp(us, …)` default). Nanosecond precision would require `int64`
   overflow guards; this is deferred to a future release.

3. **Leap seconds**: T does not model leap seconds (consistent with POSIX and
   Arrow). Durations spanning a leap-second boundary will be off by 1 second.

4. **`%within%` and `%--%` operators**: These infix forms require parser
   changes (new token or backtick-operator syntax). Until the parser supports
   them, use `int_within(d, iv)` and `interval(start, end)` instead.

5. **Business-day arithmetic**: `bdays(n)` (business days, optionally with a
   holiday calendar) is not part of this spec. It can be layered on top as a
   future `chrono.bizdays` sub-package.

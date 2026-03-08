let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Chrono:\n";
  test "ymd parses date" {|ymd("2024-01-15")|} "Date(2024-01-15)";
  test "ymd_hms parses datetime" {|ymd_hms("2024-01-15 09:30:00")|} "Datetime(2024-01-15T09:30:00Z[UTC])";
  test "parse_date supports month names" {|parse_date("15 Jan 2024", "%d %b %Y")|} "Date(2024-01-15)";
  test "date components extract values" {|[year(ymd("2024-07-04")), month(ymd("2024-07-04")), day(ymd("2024-07-04"))]|} "[2024, 7, 4]";
  test "month label works" {|month(ymd("2024-07-04"), label = true)|} {|"Jul"|};
  test "date arithmetic with months clamps end of month" {|ymd("2024-01-31") + months(1)|} "Date(2024-02-29)";
  test "date arithmetic with months clamps non-leap year" {|ymd("2023-01-31") + months(1)|} "Date(2023-02-28)";
  test "date subtraction returns period" {|ymd("2024-07-04") - ymd("2024-01-01")|} "Period(years=0, months=0, days=185, hours=0, minutes=0, seconds=0, micros=0)";
  test "format_date renders tokens" {|format_date(ymd("2024-07-04"), "%B %d, %Y")|} {|"July 04, 2024"|};
  test "type predicates recognize date types" {|[is_date(ymd("2024-01-01")), is_datetime(ymd_hms("2024-01-01 00:00:00"))]|} "[true, true]";
  test "floor_date rounds down hour" {|floor_date(ymd_hms("2024-01-15 09:37:42"), "hour")|} "Datetime(2024-01-15T09:00:00Z[UTC])";
  test "ceiling_date rounds up hour" {|ceiling_date(ymd_hms("2024-01-15 09:37:42"), "hour")|} "Datetime(2024-01-15T10:00:00Z[UTC])";
  test "round_date rounds to nearest hour" {|round_date(ymd_hms("2024-01-15 09:37:42"), "hour")|} "Datetime(2024-01-15T10:00:00Z[UTC])";
  test "with_tz updates timezone label" {|with_tz(ymd_hms("2024-01-15 09:30:00"), "Europe/Paris")|} "Datetime(2024-01-15T09:30:00Z[Europe/Paris])";
  test "force_tz updates timezone label" {|force_tz(ymd_hms("2024-01-15 09:30:00"), "Europe/Paris")|} "Datetime(2024-01-15T09:30:00Z[Europe/Paris])";
  test "is_leap_year on integer" {|is_leap_year(2024)|} "true";
  test "days_in_month on integers" {|days_in_month(2024, 2)|} "29";
  test "within interval" {|`%within%`(ymd("2024-01-15"), interval(ymd("2024-01-01"), ymd("2024-01-31")))|} "true";
  test "make_date creates valid date" {|make_date(year=2024, month=2, day=29)|} "Date(2024-02-29)";
  test "make_datetime creates valid datetime" {|make_datetime(year=2024, month=2, day=29, hour=13, min=40)|} "Datetime(2024-02-29T13:40:00Z[UTC])";
  test "am returns true for morning" {|am(ymd_hms("2024-01-15 09:30:00"))|} "true";
  test "pm returns true for afternoon" {|pm(ymd_hms("2024-01-15 13:30:00"))|} "true";
  test "vectorized year works on pulled dates"
    {|df = dataframe([[s: "2024-01-01"], [s: "2025-02-03"]]); year(ymd(pull(df, "s")))|}
    "Vector[2024, 2025]";
  test "today returns date type" {|type(today())|} {|"Date"|};
  test "now returns datetime type" {|type(now())|} {|"Datetime"|};
  print_newline ();

  Printf.printf "Chrono JSON serialization:\n";

  let date_json =
    Serialization.value_to_yojson (Ast.VDate (Chrono.days_from_civil 2024 1 15))
  in
  if date_json = `String "2024-01-15" then begin
    incr _pass_count; Printf.printf "  ✓ value_to_yojson serializes dates\n"
  end else begin
    incr _fail_count; Printf.printf "  ✗ value_to_yojson serializes dates\n"
  end;

  let datetime_json =
    Serialization.value_to_yojson
      (Ast.VDatetime (Chrono.datetime_of_components 2024 1 15 9 30 0 123456, Some "UTC"))
  in
  if datetime_json = `String "2024-01-15T09:30:00.123456Z[UTC]" then begin
    incr _pass_count; Printf.printf "  ✓ value_to_yojson serializes datetimes\n"
  end else begin
    incr _fail_count; Printf.printf "  ✗ value_to_yojson serializes datetimes\n"
  end;

  let period_json =
    Serialization.value_to_yojson
      (Ast.VPeriod { p_years = 1; p_months = 2; p_days = 3; p_hours = 4; p_minutes = 5; p_seconds = 6; p_micros = 7 })
  in
  if period_json =
      `Assoc [
        ("years", `Int 1); ("months", `Int 2); ("days", `Int 3);
        ("hours", `Int 4); ("minutes", `Int 5); ("seconds", `Int 6); ("micros", `Int 7)
      ] then begin
    incr _pass_count; Printf.printf "  ✓ value_to_yojson serializes periods\n"
  end else begin
    incr _fail_count; Printf.printf "  ✗ value_to_yojson serializes periods\n"
  end;

  let duration_json = Serialization.value_to_yojson (Ast.VDuration 12.5) in
  if duration_json = `Float 12.5 then begin
    incr _pass_count; Printf.printf "  ✓ value_to_yojson serializes durations\n"
  end else begin
    incr _fail_count; Printf.printf "  ✗ value_to_yojson serializes durations\n"
  end;

  let interval_json =
    Serialization.value_to_yojson
      (Ast.VInterval {
         iv_start = Chrono.datetime_of_components 2024 1 15 9 30 0 0;
         iv_end = Chrono.datetime_of_components 2024 1 15 10 0 0 0;
         iv_tz = Some "UTC";
       })
  in
  if interval_json =
      `Assoc [
        ("start", `String "2024-01-15T09:30:00Z[UTC]");
        ("end", `String "2024-01-15T10:00:00Z[UTC]");
        ("timezone", `String "UTC");
      ] then begin
    incr _pass_count; Printf.printf "  ✓ value_to_yojson serializes intervals\n"
  end else begin
    incr _fail_count; Printf.printf "  ✗ value_to_yojson serializes intervals\n"
  end;

  print_newline ()

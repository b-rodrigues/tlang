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
  test "vectorized year works on pulled dates"
    {|df = dataframe([{s: "2024-01-01"}, {s: "2025-02-03"}]); year(ymd(pull(df, "s")))|}
    "Vector[2024, 2025]";
  test "today returns date type" {|type(today())|} {|"Date"|};
  test "now returns datetime type" {|type(now())|} {|"Datetime"|};
  print_newline ()

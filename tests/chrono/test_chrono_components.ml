let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Phase 3 — Chrono: Date Component Extraction:\n";

  Printf.printf "  wday():\n";
  test "wday returns integer for Monday"
    "wday(ymd(\"2024-01-01\"))"
    "2";
  test "wday with label returns abbreviated name"
    "wday(ymd(\"2024-01-01\"), label = true)"
    {|"Mon"|};
  test "wday type check"
    "type(wday(ymd(\"2024-01-01\")))"
    {|"Int"|};
  print_newline ();

  Printf.printf "  yday():\n";
  test "yday for March 1 in leap year is 61"
    "yday(ymd(\"2024-03-01\"))"
    "61";
  test "yday for January 1 is 1"
    "yday(ymd(\"2024-01-01\"))"
    "1";
  print_newline ();

  Printf.printf "  week():\n";
  test "week for Jan 1 2024 is 1"
    "week(ymd(\"2024-01-01\"))"
    "1";
  print_newline ();

  Printf.printf "  quarter():\n";
  test "quarter for April 1 is 2"
    "quarter(ymd(\"2024-04-01\"))"
    "2";
  test "quarter for January 1 is 1"
    "quarter(ymd(\"2024-01-01\"))"
    "1";
  test "quarter for October 1 is 4"
    "quarter(ymd(\"2024-10-01\"))"
    "4";
  print_newline ();

  Printf.printf "  minute():\n";
  test "minute from datetime extracts minute"
    "minute(ymd_hms(\"2024-01-01 09:30:00\"))"
    "30";
  test "minute from date returns 0"
    "minute(ymd(\"2024-01-01\"))"
    "0";
  print_newline ();

  Printf.printf "  isoweek():\n";
  test "isoweek for Jan 1 2024 is 1"
    "isoweek(ymd(\"2024-01-01\"))"
    "1";
  print_newline ();

  Printf.printf "  isoyear():\n";
  test "isoyear for Jan 1 2024 is 2024"
    "isoyear(ymd(\"2024-01-01\"))"
    "2024";
  print_newline ();

  Printf.printf "  semester():\n";
  test "semester for June 30 is 1"
    "semester(ymd(\"2024-06-30\"))"
    "1";
  test "semester for July 1 is 2"
    "semester(ymd(\"2024-07-01\"))"
    "2";
  print_newline ();

  Printf.printf "  format_datetime():\n";
  test "format_datetime with custom format"
    "format_datetime(ymd(\"2024-01-15\"), \"%Y/%m/%d\")"
    {|"2024/01/15"|};
  test "format_datetime rejects non-date"
    "format_datetime(42, \"%Y\")"
    {|Error(TypeError: "Function `format_datetime` expects (Date|Datetime, String).")|};
  print_newline ();

  Printf.printf "  to_date():\n";
  test "to_date from string returns Date"
    "type(to_date(\"2024-01-15\"))"
    {|"Date"|};
  test "to_date rejects unparseable string"
    "to_date(\"not-a-date\")"
    {|Error(ValueError: "Function `to_date` could not parse \"not-a-date\" as a date.")|};
  print_newline ();

  Printf.printf "  to_datetime():\n";
  test "to_datetime from string returns Datetime"
    "type(to_datetime(\"2024-01-15 09:00:00\"))"
    {|"Datetime"|};
  test "to_datetime rejects unparseable string"
    "to_datetime(\"not-a-datetime\")"
    {|Error(ValueError: "Function `to_datetime` could not parse \"not-a-datetime\" as a datetime.")|};
  print_newline ();

  Printf.printf "  Date comparisons:\n";
  test "date less than" "to_date(\"2024-01-01\") < to_date(\"2024-01-02\")" "true";
  test "date greater than" "to_date(\"2024-01-02\") > to_date(\"2024-01-01\")" "true";
  test "date less-equal same" "to_date(\"2024-01-01\") <= to_date(\"2024-01-01\")" "true";
  test "date greater-equal" "to_date(\"2024-01-02\") >= to_date(\"2024-01-01\")" "true";
  test "date not less than" "to_date(\"2024-01-02\") < to_date(\"2024-01-01\")" "false";
  test "date not equal" "to_date(\"2024-01-01\") != to_date(\"2024-01-02\")" "true";
  test "date equal" "to_date(\"2024-01-01\") == to_date(\"2024-01-01\")" "true";
  print_newline ();

  Printf.printf "  make_period():\n";
  test "make_period returns Period"
    "type(make_period(years = 1, months = 2))"
    {|"Period"|};
  test "make_period with all zeros"
    "type(make_period())"
    {|"Period"|};
  print_newline ();
  print_newline ()

(* Dogfooding: bounds, round-trip, and idempotence invariants of the chrono
   package exercised via prop_named / prop_test over generated date and
   datetime domains, plus NA-hardening over dataframes with date columns. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — chrono:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_floor_ceil       = prop_named("floor_ceil",         \(d) floor_date(d, "month") <= d && ceiling_date(d, "month") >= d)
      m_floor_idem       = prop_named("floor_idem",         \(d) floor_date(floor_date(d, "month"), "month") == floor_date(d, "month"))
      m_ceil_idem        = prop_named("ceil_idem",          \(d) ceiling_date(ceiling_date(d, "month"), "month") == ceiling_date(d, "month"))
      m_round_idem       = prop_named("round_idem",         \(d) round_date(round_date(d, "month"), "month") == round_date(d, "month"))
      m_day_bound        = prop_named("day_bound",          \(d) day(d) >= 1 && day(d) <= days_in_month(year(d), month(d)))
      m_month_bound      = prop_named("month_bound",        \(d) month(d) >= 1 && month(d) <= 12)
      m_quarter_semester = prop_named("quarter_semester",   \(d) quarter(d) >= 1 && quarter(d) <= 4 && semester(d) >= 1 && semester(d) <= 2)
      m_yday_bound       = prop_named("yday_bound",         \(d) yday(d) >= 1 && yday(d) <= 366)
      m_isoweek_bound    = prop_named("isoweek_bound",      \(d) isoweek(d) >= 1 && isoweek(d) <= 53)
      m_wday_bound       = prop_named("wday_bound",         \(d) wday(d) >= 1 && wday(d) <= 7)
      m_leap_consistent  = prop_named("leap_consistent",    \(d) is_leap_year(year(d)) == (days_in_month(year(d), 2) == 29))
      m_format_roundtrip = prop_named("format_roundtrip",   \(d) parse_date(format_date(d, "%Y-%m-%d"), "%Y-%m-%d") == d)
      m_ymd_roundtrip    = prop_named("ymd_roundtrip",      \(d) ymd(format_date(d, "%Y%m%d")) == d)
      m_to_date_id       = prop_named("to_date_id",         \(d) to_date(d) == d)
      m_period_roundtrip = prop_named("period_roundtrip",   \(d) (d + make_period(days = 5)) - d == make_period(days = 5))
      m_period_monotone  = prop_named("period_monotone",    \(d) d + make_period(days = 1) > d)
      m_within_iv        = prop_named("within_iv",          \(d) d %within% interval(ymd("1999-01-01"), ymd("2025-12-31")))
      m_dt_hour          = prop_named("dt_hour",            \(dt) hour(dt) >= 0 && hour(dt) <= 23)
      m_dt_minute        = prop_named("dt_minute",          \(dt) minute(dt) >= 0 && minute(dt) <= 59)
      m_dt_second        = prop_named("dt_second",          \(dt) second(dt) >= 0.0 && second(dt) < 60.0)
      m_dt_ampm          = prop_named("dt_ampm",            \(dt) am(dt) == (hour(dt) < 12) && pm(dt) == (hour(dt) >= 12))
      m_dt_to_date       = prop_named("dt_to_date",         \(dt) year(to_date(dt)) == year(dt))
      m_dt_period_rt     = prop_named("dt_period_rt",       \(dt) (dt + make_period(hours = 1)) - make_period(hours = 1) == dt)
      m_mutate_nrow      = prop_named("mutate_nrow",        \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df))
      m_arrange_nrow     = prop_named("arrange_nrow",       \(df) nrow(arrange(df, $d)) == nrow(df))
    |} env
  in

  let date_gen     = "prop_gen_ymd(2000, 2024)" in
  let datetime_gen = "prop_gen_date_range(ymd_hms(\"2020-01-01 00:00:00\"), ymd_hms(\"2024-12-31 23:59:59\"))" in
  let df_date_gen  = "prop_gen_df([d: prop_gen_ymd(2000, 2024), x: prop_gen_int_range(0, 100)], nrows = 40, na_prob = 0.3)" in

  test_env env "floor(d) <= d <= ceiling(d) (month)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_floor_ceil, %s, n = 30)" date_gen) "PASS";

  test_env env "floor_date is idempotent"
    (Printf.sprintf "set_seed(1)\nprop_test(m_floor_idem, %s, n = 30)" date_gen) "PASS";

  test_env env "ceiling_date is idempotent"
    (Printf.sprintf "set_seed(1)\nprop_test(m_ceil_idem, %s, n = 30)" date_gen) "PASS";

  test_env env "round_date is idempotent"
    (Printf.sprintf "set_seed(1)\nprop_test(m_round_idem, %s, n = 30)" date_gen) "PASS";

  test_env env "day of month within month length"
    (Printf.sprintf "set_seed(1)\nprop_test(m_day_bound, %s, n = 30)" date_gen) "PASS";

  test_env env "month in [1, 12]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_month_bound, %s, n = 30)" date_gen) "PASS";

  test_env env "quarter in [1, 4] and semester in [1, 2]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_quarter_semester, %s, n = 30)" date_gen) "PASS";

  test_env env "yday in [1, 366]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_yday_bound, %s, n = 30)" date_gen) "PASS";

  test_env env "isoweek in [1, 53]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_isoweek_bound, %s, n = 30)" date_gen) "PASS";

  test_env env "wday in [1, 7]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_wday_bound, %s, n = 30)" date_gen) "PASS";

  test_env env "is_leap_year consistent with February days"
    (Printf.sprintf "set_seed(1)\nprop_test(m_leap_consistent, %s, n = 30)" date_gen) "PASS";

  test_env env "format_date + parse_date round-trip"
    (Printf.sprintf "set_seed(1)\nprop_test(m_format_roundtrip, %s, n = 30)" date_gen) "PASS";

  test_env env "format_date(%Y%m%d) + ymd round-trip"
    (Printf.sprintf "set_seed(1)\nprop_test(m_ymd_roundtrip, %s, n = 30)" date_gen) "PASS";

  test_env env "to_date(d) == d"
    (Printf.sprintf "set_seed(1)\nprop_test(m_to_date_id, %s, n = 30)" date_gen) "PASS";

  test_env env "(d + 5 days) - d == 5 days"
    (Printf.sprintf "set_seed(1)\nprop_test(m_period_roundtrip, %s, n = 30)" date_gen) "PASS";

  test_env env "adding a day moves forward"
    (Printf.sprintf "set_seed(1)\nprop_test(m_period_monotone, %s, n = 30)" date_gen) "PASS";

  test_env env "date within covering interval"
    (Printf.sprintf "set_seed(1)\nprop_test(m_within_iv, %s, n = 30)" date_gen) "PASS";

  test_env env "hour in [0, 23]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_dt_hour, %s, n = 30)" datetime_gen) "PASS";

  test_env env "minute in [0, 59]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_dt_minute, %s, n = 30)" datetime_gen) "PASS";

  test_env env "second in [0, 60)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_dt_second, %s, n = 30)" datetime_gen) "PASS";

  test_env env "am/pm complement hour < 12"
    (Printf.sprintf "set_seed(1)\nprop_test(m_dt_ampm, %s, n = 30)" datetime_gen) "PASS";

  test_env env "to_date preserves the year"
    (Printf.sprintf "set_seed(1)\nprop_test(m_dt_to_date, %s, n = 30)" datetime_gen) "PASS";

  test_env env "datetime period round-trip (dt + 1h) - 1h == dt"
    (Printf.sprintf "set_seed(1)\nprop_test(m_dt_period_rt, %s, n = 30)" datetime_gen) "PASS";

  test_env env "mutate preserves nrow with NA dates"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mutate_nrow, %s, n = 30)" df_date_gen) "PASS";

  test_env env "arrange by date preserves nrow with NA dates"
    (Printf.sprintf "set_seed(1)\nprop_test(m_arrange_nrow, %s, n = 30)" df_date_gen) "PASS";

  Printf.printf "\n"

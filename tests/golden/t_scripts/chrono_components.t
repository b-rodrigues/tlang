-- Test: chrono parsing and component extraction
df = dataframe([
  {label: "leap", date_str: "2024-01-31", ts_str: "2024-07-04 14:30:45", custom_date: "15 Jan 2024"},
  {label: "common", date_str: "2023-01-31", ts_str: "2024-01-15 09:05:07", custom_date: "03 Feb 2025"}
])

result = df
  |> mutate($d = ymd($date_str))
  |> mutate($dt = ymd_hms($ts_str))
  |> mutate($custom = parse_date($custom_date, "%d %b %Y"))
  |> mutate($next_month = $d + months(1))
  |> mutate($year = year($d))
  |> mutate($month_label = month($d, label = true))
  |> mutate($month_num = month($d))
  |> mutate($day_num = day($d))
  |> mutate($weekday = wday($d, label = true))
  |> mutate($yday_num = yday($d))
  |> mutate($quarter_num = quarter($d))
  |> mutate($next_month_fmt = format_date($next_month, "%Y-%m-%d"))
  |> mutate($custom_fmt = format_date($custom, "%Y-%m-%d"))
  |> mutate($dt_fmt = format_datetime($dt, "%Y-%m-%d %H:%M:%S"))
  |> select($label, $year, $month_label, $month_num, $day_num, $weekday, $yday_num, $quarter_num, $next_month_fmt, $custom_fmt, $dt_fmt)

write_csv(result, "tests/golden/t_outputs/chrono_components.csv")
print("✓ chrono components complete")

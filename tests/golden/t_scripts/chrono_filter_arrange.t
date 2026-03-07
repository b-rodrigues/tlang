-- Test: chrono comparison, filter, and arrange integration
df = dataframe([
  {name: "b", date_str: "2024-02-10"},
  {name: "a", date_str: "2023-12-31"},
  {name: "c", date_str: "2024-01-15"}
])

result = df
  |> mutate($d = ymd($date_str))
  |> filter($d >= ymd("2024-01-01"))
  |> arrange($d, "desc")
  |> mutate($date_fmt = format_date($d, "%Y-%m-%d"))
  |> select($name, $date_fmt)

write_csv(result, "tests/golden/t_outputs/chrono_filter_arrange.csv")
print("✓ chrono filter/arrange complete")

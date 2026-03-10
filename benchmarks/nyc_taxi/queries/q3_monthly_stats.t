input_path = env("NYC_TAXI_CSV")

if (type(input_path) == "Null") {
  print("Set NYC_TAXI_CSV to a materialized NYC taxi CSV file before running this benchmark.")
  exit(1)
} else {
  df = read_csv(input_path)

  result = df
    |> filter($trip_distance > 5)
    |> group_by($year, $month)
    |> summarize($avg_fare = mean($fare_amount, na_rm = true), $trips = nrow($year))

  print(result)
  print("ROWS_SCANNED=")
  print(nrow(df))
  print("ROWS_RETURNED=")
  print(nrow(result))
}

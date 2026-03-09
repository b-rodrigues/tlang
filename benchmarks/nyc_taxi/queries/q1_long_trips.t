input_path = env("NYC_TAXI_CSV")

if (type(input_path) == "Null") {
  print(error("ValueError", "Set NYC_TAXI_CSV to a materialized NYC taxi CSV file before running this benchmark."))
} else {
  df = read_csv(input_path)

  result = df
    |> filter($trip_distance > 10)
    |> summarize($avg_fare = mean($fare_amount), $trips = nrow($fare_amount))

  print(result)
  print("ROWS_SCANNED=")
  print(nrow(df))
  print("ROWS_RETURNED=")
  print(nrow(result))
}

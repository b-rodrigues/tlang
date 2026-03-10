input_path = env("NYC_TAXI_CSV")
arrow_path = env("NYC_TAXI_ARROW")

if (type(input_path) == "Null") {
  print("Set NYC_TAXI_CSV to a materialized NYC taxi CSV file before running this benchmark.")
  exit(1)
} else {
  if (type(arrow_path) == "Null") {
    df = read_csv(input_path)
  } else {
    if (file_exists(arrow_path)) {
      df = read_arrow(arrow_path)
    } else {
      df = read_csv(input_path)
    }
  }

  result = df
    |> group_by($passenger_count)
    |> summarize($avg_fare = mean($fare_amount, na_rm = true), $trips = nrow($passenger_count))

  print(result)
  print("ROWS_SCANNED=")
  print(nrow(df))
  print("ROWS_RETURNED=")
  print(nrow(result))
}

input_csv = env("NYC_TAXI_CSV")
input_parquet = env("NYC_TAXI_PARQUET")

if (type(input_parquet) == "String") {
  df = read_parquet(input_parquet)
} else if (type(input_csv) == "String") {
  df = read_csv(input_csv)
} else {
  print("Set NYC_TAXI_CSV or NYC_TAXI_PARQUET to a materialized NYC taxi file before running this benchmark.")
  exit(1)
}

result = df
  |> filter(!is_na($fare_amount) && !is_na($tip_amount) && $total_amount > 0)
  |> group_by($VendorID, $RatecodeID, $PULocationID, $DOLocationID)
  |> summarize(
       $avg_fare = mean($fare_amount, na_rm = true),
       $avg_tip = mean($tip_amount, na_rm = true),
       $avg_total = mean($total_amount, na_rm = true),
       $total_tolls = sum($tolls_amount, na_rm = true),
       $trips = n(),
       $max_passengers = max($passenger_count, na_rm = true)
     )
  |> arrange($trips, "desc")

print(result |> head(n = 10))
print(str_join(["ROWS_SCANNED=", str_string(nrow(df))]))
print(str_join(["ROWS_RETURNED=", str_string(nrow(result))]))

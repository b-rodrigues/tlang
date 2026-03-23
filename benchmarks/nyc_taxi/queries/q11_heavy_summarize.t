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
  |> filter(!is_na($trip_distance))
  |> group_by($VendorID)
  |> summarize(
       $mean_fare = mean($fare_amount, na_rm = true),
       $mean_tip = mean($tip_amount, na_rm = true),
       $total_rev = sum($total_amount, na_rm = true),
       $max_dist = max($trip_distance),
       $min_dist = min($trip_distance),
       $total_passengers = sum($passenger_count, na_rm = true),
       $trips = n(),
       $unique_locs = n_distinct($PULocationID)
     )

print(result |> head(n = 10))
print(str_join(["ROWS_SCANNED=", str_string(nrow(df))]))
print(str_join(["ROWS_RETURNED=", str_string(nrow(result))]))

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
  |> select($year, $month, $VendorID, $payment_type, $PULocationID, $trip_distance, $fare_amount, $tip_amount, $total_amount)
  |> filter(!is_na($trip_distance) && !is_na($fare_amount) && $trip_distance > 0 && $total_amount > 0)
  |> mutate(
       $fare_per_mile = $fare_amount / $trip_distance,
       $tip_percent = ($tip_amount / $total_amount) * 100.0
     )
  |> group_by($year, $month, $VendorID, $payment_type)
  |> summarize(
       $avg_fare_per_mile = mean($fare_per_mile, na_rm = true),
       $avg_tip_percent = mean($tip_percent, na_rm = true),
       $total_revenue = sum($total_amount, na_rm = true),
       $max_trip_distance = max($trip_distance, na_rm = true),
       $rides = n(),
       $unique_pickups = n_distinct($PULocationID)
     )
  |> arrange($total_revenue, "desc")

print(result |> head(n = 10))
print(str_join(["ROWS_SCANNED=", str_string(nrow(df))]))
print(str_join(["ROWS_RETURNED=", str_string(nrow(result))]))

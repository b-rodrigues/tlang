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
  |> filter($total_amount > 0)
  |> mutate($tip_percent = ($tip_amount / $total_amount) * 100.0)

print(result |> head(n = 10))
print(str_join(["ROWS_SCANNED=", str_string(nrow(df))]))
print(str_join(["ROWS_RETURNED=", str_string(nrow(result))]))

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

grouped = df
  |> select($year, $month, $VendorID, $total_amount)
  |> group_by($year, $month, $VendorID)
  |> summarize($rev = sum($total_amount, na_rm = true))
  |> mutate($vendor_label = if (is_na($VendorID)) "vendor_NA" else str_join(["vendor_", str_string($VendorID)]))
  |> select($year, $month, $vendor_label, $rev)

result = grouped |> pivot_wider(names_from = $vendor_label, values_from = $rev)

print(result |> head(n = 10))
print(str_join(["ROWS_SCANNED=", str_string(nrow(df))]))
print(str_join(["ROWS_RETURNED=", str_string(nrow(result))]))

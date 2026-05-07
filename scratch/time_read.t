input_parquet = env("NYC_TAXI_PARQUET")
df = read_parquet(input_parquet)
print(str_join(["Rows: ", str_string(nrow(df))]))

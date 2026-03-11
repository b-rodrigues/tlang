df = read_csv("tests/golden/data/separate_data.csv")
glimpse(df)
result = df |> separate($date, into = ["year", "month", "day"], sep = "-")
print("result is:", result)

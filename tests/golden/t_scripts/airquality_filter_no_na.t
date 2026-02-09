-- Test: Filter out NAs
-- Note: NA handling may not be implemented yet
df = read_csv("tests/golden/data/data_with_nas.csv")
-- This is a placeholder for when NA handling is implemented
-- result = df |> filter(\(row) !is_na(row.Ozone))
-- For now, skip this test
print("⚠ filter(!is.na(Ozone)) - not yet implemented")

-- Test: Mean with na.rm
-- Note: NA handling may not be implemented yet
df = read_csv("tests/golden/data/data_with_nas.csv")
-- This is a placeholder for when NA handling is implemented
-- result = summarize(df, "mean_ozone", mean(df.Ozone, na_rm=true), "mean_solar", mean(df.Solar.R, na_rm=true))
-- For now, skip this test
print("⚠ mean with na.rm - not yet implemented")

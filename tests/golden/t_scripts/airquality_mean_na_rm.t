-- Test: Mean with na.rm
-- Compares to: data_with_nas %>% summarize(mean_ozone = mean(Ozone, na.rm = TRUE), mean_solar = mean(Solar.R, na.rm = TRUE))
df = read_csv("tests/golden/data/data_with_nas.csv")
result = summarize(df, $mean_ozone = mean($Ozone, na_rm = true), $mean_solar = mean($Solar.R, na_rm = true))
write_csv(result, "tests/golden/t_outputs/airquality_mean_na_rm.csv")
print("✓ summarize with mean(na_rm=true) complete")

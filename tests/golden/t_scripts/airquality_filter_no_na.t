-- Test: Filter out NAs
-- Compares to: dplyr::filter(!is.na(Ozone))
df = read_csv("tests/golden/data/data_with_nas.csv")
result = df |> filter(not is_na($Ozone))
write_csv(result, "tests/golden/t_outputs/airquality_filter_no_na.csv")
print("✓ filter(!is.na(Ozone)) complete")

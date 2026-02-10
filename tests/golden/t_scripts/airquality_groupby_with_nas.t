-- Test: Group by with NAs
-- Compares to: data_with_nas %>% mutate(temp_category = ifelse(Temp > 75, "hot", "cool")) %>% group_by(temp_category) %>% summarize(mean_ozone = mean(Ozone, na.rm = TRUE), count = n())
df = read_csv("tests/golden/data/data_with_nas.csv")
step1 = df |> mutate("temp_category", \(row) if (row.Temp > 75) "hot" else "cool")
result = step1 |> group_by("temp_category") |> summarize("mean_ozone", \(g) mean(g.Ozone, na_rm = true), "count", \(g) nrow(g))
write_csv(result, "tests/golden/t_outputs/airquality_groupby_with_nas.csv")
print("✓ group_by with NAs complete")

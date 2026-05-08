-- tests/golden/t_scripts/julia_tidier_groupby.t
df = read_csv("tests/golden/data/julia_simple_data.csv")
res = df |> 
  mutate($age_group = ifelse($age > 30, "old", "young")) |>
  group_by($age_group) |>
  summarize($mean_score = mean($score), $count = n()) |>
  arrange($age_group) -- Ensure deterministic order for comparison
write_csv(res, "tests/golden/t_outputs/julia_tidier_groupby.csv")
print("✓ julia_tidier_groupby")

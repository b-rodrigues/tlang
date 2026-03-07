-- Test: month example
df = dataframe([
  [m: "Dec"],
  [m: "Apr"],
  [m: "Jan"],
  [m: "Mar"]
])
lvls = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
res = df |> mutate($m_fct = factor($m, levels = lvls)) |> arrange($m_fct)
write_csv(res, "tests/golden/t_outputs/factor_months_sort.csv")
print("✓ months")

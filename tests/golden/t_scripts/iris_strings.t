-- Test: String operations on Iris Species
df = read_csv("tests/golden/data/iris.csv")
result = df 
  |> mutate(
    species_upper = to_upper($Species),
    species_lower = to_lower($Species),
    len = length($Species),
    sub = substring($Species, 0, 3),
    joined = join($Species), -- Test join on column with default sep=""
    has_set = contains($Species, "set"),
    rep_first = replace_first($Species, "s", "S"),
    rep_all = replace($Species, "s", "S")
  )
write_csv(result, "tests/golden/t_outputs/iris_strings.csv")
print("✓ String operations on Iris Species complete")

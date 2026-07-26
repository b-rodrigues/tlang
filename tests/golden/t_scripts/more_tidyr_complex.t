mt = read_csv("data/mtcars.csv", sep = "|")

-- nest/unnest
mt_nested = nest(mt, data = starts_with("mpg"))
mt_un = unnest(mt_nested, $data)
write_csv(mt_un, "tests/golden/t_outputs/tidyr_nest_unnest.csv")

-- separate_rows
df_sep = to_dataframe([
  [id: 1, tags: "a,b,c"],
  [id: 2, tags: "d,e"]
])
df_seped = separate_rows(df_sep, $tags, sep = ",")
write_csv(df_seped, "tests/golden/t_outputs/tidyr_separate_rows.csv")

-- uncount
df_weights = to_dataframe([
  [x: "a", w: 3],
  [x: "b", w: 2]
])
df_expanded = uncount(df_weights, $w)
write_csv(df_expanded, "tests/golden/t_outputs/tidyr_uncount.csv")

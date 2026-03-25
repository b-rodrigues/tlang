mt = read_csv("data/mtcars.csv", sep = "|")

print("--- nest/unnest ---")
-- Matchers! This will nest 'mpg'
mt_nested = nest(mt, data = starts_with("mpg"))
print("Nested nrow:")
print(nrow(mt_nested))
print("Nested colnames:")
print(colnames(mt_nested))

mt_un = unnest(mt_nested, $data)
print("Unnested nrow:")
print(nrow(mt_un))
print("Unnested ncol:")
print(ncol(mt_un))

print("--- separate_rows ---")
df_sep = dataframe([
  [id: 1, tags: "a,b,c"],
  [id: 2, tags: "d,e"]
])
df_seped = separate_rows(df_sep, $tags, sep = ",")
print("Separated rows nrow:")
print(nrow(df_seped))
print(df_seped)

print("--- uncount ---")
df_weights = dataframe([
  [x: "a", w: 3],
  [x: "b", w: 2]
])
df_expanded = uncount(df_weights, $w)
print("Uncounted nrow:")
print(nrow(df_expanded))
print(df_expanded)
print("✓ more_tidyr_complex complete")

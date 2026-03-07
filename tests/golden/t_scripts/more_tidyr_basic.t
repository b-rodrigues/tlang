mt = read_csv("data/mtcars.csv", sep = "|")

print("--- rename ---")
mt_renamed = rename(mt, miles_per_gallon = $mpg, cylinders = $cyl)
print(head(colnames(mt_renamed), 4))

print("--- relocate ---")
mt_relocated = relocate(mt, $gear, $carb, .before = $mpg)
print(head(colnames(mt_relocated), 4))

print("--- distinct ---")
df_dup = dataframe([
  [a: 1, b: 1],
  [a: 1, b: 1],
  [a: 2, b: 2]
])
print("Original nrow:")
print(nrow(df_dup))
print("Distinct nrow:")
print(nrow(distinct(df_dup)))

print("--- slice ---")
mt_sliced = slice(mt, [0, 1, 2])
print(nrow(mt_sliced))

print("--- count ---")
print(count(mt, $cyl))

print("--- slice_max ---")
print(slice_max(mt, $mpg, n = 3))

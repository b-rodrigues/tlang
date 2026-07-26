mt = read_csv("data/mtcars.csv", sep = "|")

-- rename
mt_renamed = rename(mt, miles_per_gallon = $mpg, cylinders = $cyl)
write_csv(mt_renamed |> head(4) |> select($miles_per_gallon, $cylinders, $disp, $hp), "tests/golden/t_outputs/tidyr_rename.csv")

-- relocate
mt_relocated = relocate(mt, $gear, $carb, .before = $mpg)
write_csv(mt_relocated |> head(4) |> select($gear, $carb, $mpg, $cyl), "tests/golden/t_outputs/tidyr_relocate.csv")

-- distinct
df_dup = to_dataframe([
  [a: 1, b: 1],
  [a: 1, b: 1],
  [a: 2, b: 2]
])
write_csv(distinct(df_dup), "tests/golden/t_outputs/tidyr_distinct.csv")

-- slice
mt_sliced = slice(mt, [0, 1, 2])
write_csv(mt_sliced, "tests/golden/t_outputs/tidyr_slice.csv")

-- count
write_csv(count(mt, $cyl), "tests/golden/t_outputs/tidyr_count.csv")

-- slice_max
write_csv(slice_max(mt, $mpg, n = 3), "tests/golden/t_outputs/tidyr_slice_max.csv")

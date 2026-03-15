data_dir = "tests/golden/data"
output_dir = "tests/golden/t_outputs"

iris = read_csv(path_join(data_dir, "iris.csv"))

-- 1. Basic Enquo Pattern
my_mutate = \(col: Any -> DataFrame) {
  col_enq = enquo(col)
  e = expr(iris |> mutate(!!col_enq := !!col_enq + 10.0))
  eval(e)
}

iris_mutated = my_mutate($`Sepal.Length`)
write_csv(iris_mutated, path_join(output_dir, "metaprog_enquo_mutate.csv"))

-- 2. Enquos Pattern
my_summarize = \(... -> DataFrame) {
  cols = enquos(...)
  e = expr(iris |> summarize(!!!cols))
  eval(e)
}

iris_summary = my_summarize(`mean_Sepal.Length` = mean($`Sepal.Length`), 
                            `mean_Sepal.Width` = mean($`Sepal.Width`))
write_csv(iris_summary, path_join(output_dir, "metaprog_enquos_summarize.csv"))

-- 3. Quasiquoted Expression Building (quo captures environment at build time)
build_expr = \(x: Any -> Any) quo(!!x + 5)
res = build_expr(quo(10 + 10))

res_df = eval(expr(iris
  |> summarize(val = !!res)
  |> head(1)))

write_csv(res_df, path_join(output_dir, "metaprog_expr_building.csv"))

-- 4. Quos Pattern
multi_quos = quos(a = 1 + 1, b = 2 + 2)
write_csv(iris |> head(1) |> mutate(!!!multi_quos), path_join(output_dir, "metaprog_quos.csv"))

-- 5. Dynamic Name in Mutate
new_name = "Sepal.Large"
res_dyn = iris |> head(1) |> mutate(!!new_name := $`Sepal.Length` >= 5.1)
write_csv(res_dyn, path_join(output_dir, "metaprog_dyn_name.csv"))

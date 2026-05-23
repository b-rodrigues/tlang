p = pipeline {
  calc = node(command = <{ 
    df = DataFrame(x = [1, 2, 3], y = [10, 20, 30])
    df[!, :z] = df.x .* df.y
    df
  }>, runtime = Julia, serializer = ^csv)
}
res = build_pipeline(p)
if (is_error(res)) {
  print("PIPELINE FAILED!")
  print(read_log("calc"))
  exit(1)
}
write_csv(read_node(p.calc), "tests/golden/t_outputs/julia_simple.csv")

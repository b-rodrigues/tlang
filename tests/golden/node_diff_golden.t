-- Golden test: compare the same node across two builds
-- Assumes two historical build logs exist for the same pipeline.

p = pipeline {
  customers = read_csv("tests/golden/data/iris.csv")
}

hist = build_log_history(p, n = 2)
assert(nrow(hist) >= 2)

d = node_diff(p.customers, p.customers,
      log_a = 2,
      log_b = 1,
      key = [$Sepal_Length, $Sepal_Width, $Petal_Length, $Petal_Width, $Species])

assert(d.kind == "dataframe_diff")
assert(type(d.summary) == "Dict")
assert(type(d.hunks) == "List")

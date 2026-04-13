-- Test: mocked plot metadata artifacts can be read through read_node()
run("mkdir -p _pipeline tests/golden/t_outputs/mock_plot_metadata")

ggplot_artifact = "tests/golden/t_outputs/mock_plot_metadata/ggplot.json"
matplotlib_artifact = "tests/golden/t_outputs/mock_plot_metadata/matplotlib.json"

t_write_json([
  class: "ggplot",
  backend: "R",
  title: "Fuel economy",
  mapping: [x: "wt", y: "mpg"],
  labels: [x: "Weight", y: "Miles per gallon"],
  layers: ["Point"],
  _display_keys: ["class", "backend", "title", "mapping", "labels", "layers"]
], ggplot_artifact)

t_write_json([
  class: "matplotlib",
  backend: "plotnine",
  title: "Scatter plot",
  mapping: [x: "wt", y: "mpg"],
  labels: [x: "wt", y: "mpg"],
  layers: ["point"],
  _display_keys: ["class", "backend", "title", "mapping", "labels", "layers"]
], matplotlib_artifact)

build_log = [
  timestamp: "20260413-plot-meta",
  hash: "plotmeta",
  out_path: "/tmp",
  nodes: [
    [
      node: "ggplot_meta",
      path: ggplot_artifact,
      runtime: "R",
      serializer: "default",
      class: "ggplot",
      dependencies: []
    ],
    [
      node: "matplotlib_meta",
      path: matplotlib_artifact,
      runtime: "Python",
      serializer: "default",
      class: "matplotlib",
      dependencies: []
    ]
  ]
]
t_write_json(build_log, "_pipeline/build_log_plot_metadata.json")

g = read_node("ggplot_meta", which_log = "plot_metadata")
m = read_node("matplotlib_meta", which_log = "plot_metadata")

result = dataframe([
  class: [g.class, m.class],
  backend: [g.backend, m.backend],
  title: [g.title, m.title],
  x: [g.mapping.x, m.mapping.x],
  y: [g.mapping.y, m.mapping.y],
  layer_count: [length(g.layers), length(m.layers)]
])

write_csv(result, "tests/golden/t_outputs/plot_metadata_mocked.csv")
print("✓ mocked plot metadata read_node complete")

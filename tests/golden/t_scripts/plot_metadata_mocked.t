-- Test: mocked plot metadata artifacts can be read through read_node()
run("mkdir -p _pipeline tests/golden/t_outputs/mock_plot_metadata/ggplot")
run("mkdir -p _pipeline tests/golden/t_outputs/mock_plot_metadata/matplotlib")

ggplot_dir = "tests/golden/t_outputs/mock_plot_metadata/ggplot"
matplotlib_dir = "tests/golden/t_outputs/mock_plot_metadata/matplotlib"

ggplot_artifact = path_join(ggplot_dir, "artifact")
matplotlib_artifact = path_join(matplotlib_dir, "artifact")

-- Write dummy artifacts
write_text(ggplot_artifact, "rds-mock")
write_text(matplotlib_artifact, "pkl-mock")

t_write_json([
  class: "ggplot",
  backend: "R",
  title: "Fuel economy",
  mapping: [x: "wt", y: "mpg"],
  labels: [x: "Weight", y: "Miles per gallon"],
  layers: ["Point"],
  _display_keys: ["class", "backend", "title", "mapping", "labels", "layers"]
], path_join(ggplot_dir, "viz"))

t_write_json([
  class: "matplotlib",
  backend: "plotnine",
  title: "Scatter plot",
  mapping: [x: "wt", y: "mpg"],
  labels: [x: "wt", y: "mpg"],
  layers: ["point"],
  _display_keys: ["class", "backend", "title", "mapping", "labels", "layers"]
], path_join(matplotlib_dir, "viz"))

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

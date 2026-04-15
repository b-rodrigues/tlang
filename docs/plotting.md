# Plotting and Visual Inspection

T is primarily an orchestration engine and does not currently provide its own native low-level plotting library. Instead, T's `show_plot()` function supports a wide range of visualization libraries across R and Python:

- **R**: `ggplot2`
- **Python**: `matplotlib`, `seaborn`, `plotly`, `altair`, `plotnine`

One of T's unique features is **Automated Visual Metadata Capture**. When you generate a plot in an R or Python node, T "sees" the plot object and automatically extracts its structural metadata during the build process.

---

## Plotting in Polyglot Pipelines

Generating a plot in T is as simple as returning a plot object from a foreign-language node.

### Example: ggplot2 in R

```t
p = pipeline {
    p_ggplot = rn(
        command = <{
            library(ggplot2)
            ggplot(mtcars, aes(x = wt, y = mpg)) +
                geom_point() +
                labs(title = "Fuel Economy")
        }>
    )
}
```

### Example: matplotlib in Python

```t
    p = pipeline {
      p_matplotlib = pyn(
        command = <{
            import matplotlib.pyplot as plt
            fig, ax = plt.subplots()
            ax.scatter([2.6, 3.2, 3.4], [21.0, 19.2, 18.1])
            ax.set_title("Fuel Economy")
            fig
        }>
      )
    }
```

In both cases, T recognizes that the node result is a visualization.

---

## Visual Metadata Capture

When you build a pipeline containing these nodes, T creates two artifacts for each plotting node in the Nix store:
1.  **The Artifact**: The serialized plot object (e.g., an RDS file for `ggplot2`).
2.  **The Metadata (`viz`)**: A JSON representation of the plot's contents.

T automatically extracts:
- **Title**: The main title of the plot.
- **Backend**: The runtime used to produce the plot (`"R"` or `"Python"`).
- **Class**: The plot library or object type (e.g., `"ggplot"`, `"matplotlib"`, `"seaborn"`, `"plotly"`, `"altair"`).
- **Labels**: Axis labels and legends.
- **Layers**: The types of geometries present (e.g., "point", "line").
- **Mappings**: In `ggplot2`, the aesthetic mappings (x, y, color, etc.).

---

## Inspecting Plots with `read_node()`

Because T captures this metadata, you can inspect the "contents" of a plot directly from your T scripts or the REPL without needing to render it to an image.

When you call `read_node()` on a plotting node, T returns the **metadata dictionary** instead of the binary artifact.

```t
> g = read_node("p_ggplot")
> print(g.title)
"Fuel Economy"

> print(g.layers)
["point"]

> print(g.labels)
{ x: "wt", y: "mpg", title: "Fuel Economy" }
```

This "Transparent Plotting" enables programmatic verification of visualizations—for example, a test script could assert that a generated plot has the correct title and includes a regression line layer.

---

## REPL Display

Plot metadata is pretty-printed in the REPL instead of dumping raw runtime-specific structures.

For example, a `ggplot` node read through `read_node()` displays as a structured object with fields such as:

- `class`
- `backend`
- `title`
- `mapping`
- `labels`
- `layers`

This makes plotting nodes inspectable even when the underlying artifact is binary (`.rds` or Python pickle).

---

## Plotting in Literate Programming

When using [Quarto](literate-programming-quarto.html) with T pipelines, it is important to understand how `read_node()` behaves depending on the language of the code chunk.

### In T Chunks
Within a `{t}` code block, `read_node()` follows the same behavior as the REPL: it returns the **JSON metadata dictionary**. 

````markdown
```{t}
#| echo: false
g = read_node("p_ggplot")
print(g.title)
```
````
*Output: "Fuel Economy"*

This is useful for including summary information about your visualizations directly in the text of your report.

### In R and Python Chunks
To actually **render** the plot in your report, you must use an `{r}` or `{python}` chunk. However, in these environments, `read_node()` is a preprocessor token that T replaces with the **absolute path string** to the artifact in the Nix store. 

Because `read_node()` returns a path, you must manually load the artifact using the specialized reader for that language.

#### Example: Rendering a ggplot2 node in R
````markdown
```{r}
#| echo: false
# read_node("p_ggplot") becomes '/nix/store/.../artifact'
p <- readRDS(read_node("p_ggplot"))
p
```
````

#### Example: Rendering a matplotlib node in Python
````markdown
```{python}
#| echo: false
try:
    import cloudpickle as pickle
except ImportError:
    import pickle
# read_node("p_matplotlib") becomes '/nix/store/.../artifact'
with open(read_node("p_matplotlib"), "rb") as f:
    fig = pickle.load(f)
fig
```
````

This dual behavior ensures that you can use T for programmatic inspection and R/Python for high-fidelity visual rendering, all while maintaining strict Nix-based reproducibility.

---

## Opening Plots with `show_plot()`

`show_plot()` renders a plotting artifact in a fresh Nix sandbox, writes the rendered image to `_pipeline/`, and then opens the image locally.

It accepts:

- an unbuilt `rn()` / `pyn()` node
- a built `ComputedNode`
- a `read_node()` result that still points back to a built plot node

The rendered output is currently written as a PNG file under `_pipeline/`.

Add an opener in `tproject.toml` if you want to override the default viewer:

```toml
[visualization-tool]
command = "xdg-open"
```

The value must be a single executable name or an absolute path to an executable. When no custom tool is configured, T falls back to:

1. `open` on systems where it is available
2. `xdg-open` otherwise

```t
p = rn(command = <{
  library(ggplot2)
  ggplot(mtcars, aes(wt, mpg)) + geom_point()
}>)

show_plot(p)
```

`show_plot(p)` returns the local path of the rendered PNG after launching the viewer.

### Runtime Requirements

`show_plot()` renders the plot by reloading the stored artifact inside a Nix sandbox:

- **R / ggplot2** nodes require `ggplot2` to be present in `[r-dependencies].packages`.
- **Python / matplotlib** nodes require `matplotlib` and `cloudpickle` in `[py-dependencies].packages`.
- **Python / seaborn** nodes require `seaborn`, `matplotlib`, and `cloudpickle` in `[py-dependencies].packages`.
- **Python / Plotly** requires `plotly`, `kaleido` (for static image export), and `cloudpickle` in `[py-dependencies].packages`.
- **Python / Altair** requires `altair`, `vl-convert-python` (preferred), and `cloudpickle` in `[py-dependencies].packages`.
- **Python / Plotnine** requires `plotnine`, `pandas`, and `cloudpickle` in `[py-dependencies].packages`.

### Automated Dependency Detection

When you use these libraries in a `pyn()` node, T's static analyzer will automatically detect the imports and prompt you to add the required rendering dependencies to your `tproject.toml` if they are missing.

| Detected Import | Automatically Suggested Packages |
| :--- | :--- |
| `import matplotlib` | `matplotlib`, `cloudpickle` |
| `import seaborn` | `seaborn`, `matplotlib`, `cloudpickle` |
| `import plotnine` | `plotnine`, `pandas`, `cloudpickle` |
| `import plotly` | `plotly`, `kaleido`, `cloudpickle` |
| `import altair` | `altair`, `vl-convert-python`, `cloudpickle` |

Example project configuration:

```toml
[r-dependencies]
packages = ["ggplot2"]

[py-dependencies]
version = "python314"
packages = ["matplotlib", "plotnine", "seaborn", "plotly", "kaleido"]

[visualization-tool]
command = "xdg-open"
```

### Files Written to `_pipeline/`

When you call `show_plot()`, T creates local helper files in `_pipeline/`, including:

- a temporary Nix expression used for rendering
- the rendered PNG image that is opened locally

This keeps the visualization workflow aligned with T's existing pipeline artifact conventions.

See the [T Pipeline Demos](demos.html) for real-world examples of pipelines generating interactive and static reports.

# Plotting and Visual Inspection

T is primarily an orchestration engine and does not currently provide its own native low-level plotting library, and very likely never will. Instead, T leverages the powerful visualization ecosystems of **R** (`ggplot2`) and **Python** (`matplotlib`, `plotnine`) through its polyglot pipeline architecture.

One of T's unique features is **Automated Visual Metadata Capture**. When you generate a plot in an R or Python node, T "sees" the plot object and automatically extracts its structural metadata during the build process.

---

## Plotting in Polyglot Pipelines

Generating a plot in T is as simple as returning a plot object from a foreign-language node.

### Example: ggplot2 in R

```t
p = pipeline {
    data = read_csv("data.csv")

    p_ggplot = rn(
        command = <{
            library(ggplot2)
            ggplot(data, aes(x = wt, y = mpg)) +
                geom_point() +
                labs(title = "Fuel Economy")
        }>,
        deserializer = ^csv
    )
}
```

### Example: matplotlib in Python

```t
    p_matplotlib = pyn(
        command = <{
            import matplotlib.pyplot as plt
            fig, ax = plt.subplots()
            ax.scatter(data['wt'], data['mpg'])
            ax.set_title("Fuel Economy")
            fig
        }>,
        deserializer = ^csv
    )
```

In both cases, T recognizes that the node result is a visualization.

---

## Visual Metadata Capture

When you build a pipeline containing these nodes, T creates two artifacts for each plotting node in the Nix store:
1.  **The Artifact**: The serialized plot object (e.g., an RDS file for `ggplot2`).
2.  **The Metadata (`viz`)**: A JSON representation of the plot's contents.

T automatically extracts:
- **Title**: The main title of the plot.
- **Backend**: The library used (e.g., "matplotlib" or "plotnine").
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

## Plotting in Literate Programming

When using [Quarto](literate-programming-quarto.html) with T pipelines, these plotting nodes can be directly embedded in your documents. T handles the handoff so that the visual result is rendered correctly in the final HTML or PDF report.

See the [T Pipeline Demos](demos.html) for real-world examples of pipelines generating interactive and static reports.

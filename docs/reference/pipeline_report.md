# pipeline_report

Generate Pipeline Report

Generates a report summarizing the pipeline's current status, dependency graph, built nodes, unbuilt nodes, and errored/warned nodes. When target is "ssh" (default), writes a Markdown file with plain-text tables. When target is "web", writes a self-contained HTML file with an interactive Mermaid diagram, color-coded sections, and clickable nodes.

## Parameters

- **p** (`Pipeline`): The pipeline to report on.

- **which_log** (`String`): (Optional) Regex to select a specific build log.

- **file** (`String`): (Optional) Output file path. Defaults to `_pipeline/pipeline_report_<timestamp>.md` (ssh) or `.html` (web).

- **target** (`String`): = "ssh" Output format. "ssh" for Markdown, "web" for HTML.


## Returns

The path to the generated report file.

## Examples

```t
pipeline_report(p)
pipeline_report(p, target = "web")
pipeline_report(p, target = "web", file = "report.html")
pipeline_report(p, which_log = "20260615")
```

